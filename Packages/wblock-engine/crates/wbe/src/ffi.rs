//! C ABI for Swift (wBlockCoreService). See include/wbe.h.
//! Every entry point catches panics and reports failure as NULL or false;
//! the message is available from `wbe_last_error` on the calling thread.
//! Engine handles are not thread-safe; plans support concurrent compilation.

use crate::apply::{Extra, Plan, PlanRequest};
use crate::ast::SourceRef;
use crate::runtime::Engine;
use crate::webkit::to_json;
use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

pub struct WbeCompileResult {
    webkit: CString,
    runtime: CString,
    stats: CString,
}

pub struct WbePlan(Plan);

#[no_mangle]
pub unsafe extern "C" fn wbe_plan_new(request_json: *const c_char) -> *mut WbePlan {
    guard(ptr::null_mut(), || {
        let mut request: PlanRequest = serde_json::from_str(cstr(request_json, "request_json")?)
            .map_err(|error| error.to_string())?;
        for list in &mut request.lists {
            if let Some(path) = &list.path {
                if !list.text.is_empty() {
                    return Err(format!("list {} specifies both path and text", list.id));
                }
                list.text = std::fs::read_to_string(path)
                    .map_err(|error| format!("cannot read list {}: {error}", list.id))?;
            }
        }
        for target in &request.targets {
            if target
                .lists
                .iter()
                .any(|list| list.list >= request.lists.len())
            {
                return Err("target list index out of bounds".into());
            }
            if target.lists.iter().any(|list| {
                list.shard
                    .is_some_and(|(index, count)| count == 0 || index >= count)
            }) {
                return Err("invalid target shard".into());
            }
        }
        Ok(Box::into_raw(Box::new(WbePlan(Plan::new(request)))))
    })
}

#[no_mangle]
pub unsafe extern "C" fn wbe_plan_compile_target(
    plan: *const WbePlan,
    target: usize,
    extras_json: *const c_char,
) -> *mut WbeCompileResult {
    guard(ptr::null_mut(), || {
        let plan = plan.as_ref().ok_or("plan is NULL")?;
        if target >= plan.0.target_count() {
            return Err("target index out of bounds".into());
        }
        let extras: Vec<Extra> = serde_json::from_str(cstr(extras_json, "extras_json")?)
            .map_err(|error| error.to_string())?;
        let compiled = plan.0.compile_target(target, &extras);
        let mut stats =
            serde_json::to_value(&compiled.output.stats).map_err(|error| error.to_string())?;
        stats["admitted"] =
            serde_json::to_value(compiled.admitted).map_err(|error| error.to_string())?;
        Ok(Box::into_raw(Box::new(WbeCompileResult {
            webkit: to_c(to_json(&compiled.output.webkit))?,
            runtime: to_c(compiled.output.runtime.join("\n"))?,
            stats: to_c(stats.to_string())?,
        })))
    })
}

#[no_mangle]
pub unsafe extern "C" fn wbe_plan_free(plan: *mut WbePlan) {
    if !plan.is_null() {
        drop(Box::from_raw(plan));
    }
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

fn set_error(msg: &str) {
    let clean: String = msg.chars().filter(|&c| c != '\0').collect();
    LAST_ERROR.with(|e| *e.borrow_mut() = CString::new(clean).expect("no NUL"));
}

fn guard<T>(failed: T, f: impl FnOnce() -> Result<T, String>) -> T {
    set_error("");
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => value,
        Ok(Err(msg)) => {
            set_error(&msg);
            failed
        }
        Err(_) => {
            set_error("wbe: internal panic");
            failed
        }
    }
}

/// # Safety
/// `p` must be NULL or a valid NUL-terminated string.
unsafe fn cstr<'a>(p: *const c_char, what: &str) -> Result<&'a str, String> {
    if p.is_null() {
        return Err(format!("{what} is NULL"));
    }
    CStr::from_ptr(p)
        .to_str()
        .map_err(|_| format!("{what} is not UTF-8"))
}

fn to_c(s: String) -> Result<CString, String> {
    CString::new(s).map_err(|_| "output contains NUL".to_string())
}

#[no_mangle]
pub extern "C" fn wbe_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ptr())
}

/// # Safety
/// `result` must be NULL or a live pointer from `wbe_plan_compile_target`.
#[no_mangle]
pub unsafe extern "C" fn wbe_compile_webkit_json(result: *const WbeCompileResult) -> *const c_char {
    result.as_ref().map_or(ptr::null(), |r| r.webkit.as_ptr())
}

/// # Safety
/// `result` must be NULL or a live pointer from `wbe_plan_compile_target`.
#[no_mangle]
pub unsafe extern "C" fn wbe_compile_runtime_text(
    result: *const WbeCompileResult,
) -> *const c_char {
    result.as_ref().map_or(ptr::null(), |r| r.runtime.as_ptr())
}

/// # Safety
/// `result` must be NULL or a live pointer from `wbe_plan_compile_target`.
#[no_mangle]
pub unsafe extern "C" fn wbe_compile_stats_json(result: *const WbeCompileResult) -> *const c_char {
    result.as_ref().map_or(ptr::null(), |r| r.stats.as_ptr())
}

/// # Safety
/// `result` must be NULL or a live pointer from `wbe_plan_compile_target`, not yet freed.
/// Pointers from the accessors become invalid.
#[no_mangle]
pub unsafe extern "C" fn wbe_compile_free(result: *mut WbeCompileResult) {
    if !result.is_null() {
        drop(Box::from_raw(result));
    }
}

/// Builds an engine from runtime rules text and serializes it. On success
/// `*out` owns `*out_len` bytes; release them with `wbe_bytes_free`.
///
/// # Safety
/// `runtime_text` must be a valid NUL-terminated string;
/// `out` and `out_len` must be valid pointers.
#[no_mangle]
pub unsafe extern "C" fn wbe_engine_build(
    runtime_text: *const c_char,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> bool {
    if out.is_null() || out_len.is_null() {
        set_error("out is NULL");
        return false;
    }
    *out = ptr::null_mut();
    *out_len = 0;
    guard(false, || {
        let text = cstr(runtime_text, "runtime_text")?;
        let lines: Vec<String> = text.lines().map(str::to_owned).collect();
        let bytes = Engine::build(&lines).serialize().into_boxed_slice();
        *out_len = bytes.len();
        *out = Box::into_raw(bytes) as *mut u8;
        Ok(true)
    })
}

/// # Safety
/// `bytes` must be NULL or come from `wbe_engine_build` with exactly `len`.
#[no_mangle]
pub unsafe extern "C" fn wbe_bytes_free(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(bytes, len)));
    }
}

/// # Safety
/// `bytes` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn wbe_engine_open(bytes: *const u8, len: usize) -> *mut Engine {
    guard(ptr::null_mut(), || {
        if bytes.is_null() {
            return Err("bytes is NULL".into());
        }
        let bytes = slice::from_raw_parts(bytes, len);
        Ok(Box::into_raw(Box::new(Engine::deserialize(bytes)?)))
    })
}

/// # Safety
/// `engine` must be NULL or a live handle from `wbe_engine_open`; `url` a
/// valid NUL-terminated string. Free the result with `wbe_string_free`.
#[no_mangle]
pub unsafe extern "C" fn wbe_engine_lookup(
    engine: *const Engine,
    url: *const c_char,
) -> *mut c_char {
    guard(ptr::null_mut(), || {
        let engine = engine.as_ref().ok_or("engine is NULL")?;
        let url = cstr(url, "url")?;
        let json = serde_json::to_string(&engine.lookup(url)).map_err(|e| e.to_string())?;
        Ok(to_c(json)?.into_raw())
    })
}

/// # Safety
/// `engine` must be NULL or a live handle from `wbe_engine_open`, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn wbe_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// Parses one line for the rule editor. Returns the `ParsedLine` JSON.
///
/// # Safety
/// `line` must be a valid NUL-terminated string. Free the result with
/// `wbe_string_free`.
#[no_mangle]
pub unsafe extern "C" fn wbe_classify_line(line: *const c_char) -> *mut c_char {
    guard(ptr::null_mut(), || {
        let line = cstr(line, "line")?;
        let normalized = crate::normalize::adguard_to_ubo(line);
        let parsed = crate::parse_line(&normalized, SourceRef::default());
        let json = serde_json::to_string(&parsed).map_err(|e| e.to_string())?;
        Ok(to_c(json)?.into_raw())
    })
}

/// `wbe::OUTPUT_VERSION`.
#[no_mangle]
pub extern "C" fn wbe_output_version() -> u32 {
    crate::OUTPUT_VERSION
}

/// The registrable domain of `host` (`wbe::registrable_domain`), or NULL.
///
/// # Safety
/// `host` must be a valid NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn wbe_registrable_domain(host: *const c_char) -> *mut c_char {
    guard(ptr::null_mut(), || {
        match crate::registrable_domain(cstr(host, "host")?) {
            Some(root) => Ok(to_c(root.to_string())?.into_raw()),
            None => Ok(ptr::null_mut()),
        }
    })
}

/// # Safety
/// `s` must be NULL or a string returned by this library, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn wbe_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    unsafe fn take(p: *mut c_char) -> String {
        let s = CStr::from_ptr(p).to_str().unwrap().to_owned();
        wbe_string_free(p);
        s
    }

    unsafe fn last_error() -> String {
        CStr::from_ptr(wbe_last_error())
            .to_str()
            .unwrap()
            .to_owned()
    }

    unsafe fn build_bytes(rules: &str) -> Vec<u8> {
        let rules = c(rules);
        let (mut out, mut len) = (ptr::null_mut(), 0);
        assert!(wbe_engine_build(rules.as_ptr(), &mut out, &mut len));
        let bytes = slice::from_raw_parts(out, len).to_vec();
        wbe_bytes_free(out, len);
        bytes
    }

    #[test]
    fn engine_round_trip_through_c_abi() {
        unsafe {
            let bytes = build_bytes("example.com##.ad\nexample.com##+js(set-constant, a, true)");
            let engine = wbe_engine_open(bytes.as_ptr(), bytes.len());
            assert!(!engine.is_null(), "{}", last_error());
            let url = c("https://example.com/");
            let json = take(wbe_engine_lookup(engine, url.as_ptr()));
            assert!(json.contains(r#""hide":[".ad"]"#), "{json}");
            assert!(
                json.contains(r#""scriptlets":[["set-constant","a","true"]]"#),
                "{json}"
            );
            wbe_engine_free(engine);
        }
    }

    #[test]
    fn null_and_invalid_inputs_fail_cleanly() {
        unsafe {
            let (mut out, mut len) = (ptr::null_mut(), 0);
            assert!(!wbe_engine_build(ptr::null(), &mut out, &mut len));
            assert!(last_error().contains("runtime_text is NULL"));
            assert!(out.is_null());

            assert!(wbe_engine_open(ptr::null(), 0).is_null());
            assert!(wbe_engine_open([1u8, 2, 3].as_ptr(), 3).is_null());
            assert!(last_error().contains("engine"));

            assert!(wbe_engine_lookup(ptr::null(), c("https://a/").as_ptr()).is_null());
            let empty = build_bytes("");
            let engine = wbe_engine_open(empty.as_ptr(), empty.len());
            assert!(wbe_engine_lookup(engine, ptr::null()).is_null());
            assert!(last_error().contains("url is NULL"));
            wbe_engine_free(engine);

            assert!(wbe_classify_line(ptr::null()).is_null());

            wbe_engine_free(ptr::null_mut());
            wbe_compile_free(ptr::null_mut());
            wbe_string_free(ptr::null_mut());
            wbe_bytes_free(ptr::null_mut(), 0);
        }
    }

    #[test]
    fn invalid_utf8_is_an_error() {
        unsafe {
            let bad: [c_char; 3] = [0x66, -1, 0];
            assert!(wbe_classify_line(bad.as_ptr()).is_null());
            assert!(last_error().contains("not UTF-8"));
        }
    }

    #[test]
    fn plan_rejects_invalid_shards_and_compiles_admissions() {
        unsafe {
            let invalid = c(
                r#"{"safari":[18,0],"lists":[{"id":"list","text":"||example.com^"}],"targets":[{"slot":1,"lists":[{"list":0,"shard":[0,0]}]}]}"#,
            );
            assert!(wbe_plan_new(invalid.as_ptr()).is_null());
            assert!(last_error().contains("invalid target shard"));

            let request = c(
                r#"{"safari":[18,0],"lists":[{"id":"list","text":"||example.com^"}],"targets":[{"slot":1,"lists":[{"list":0}]}]}"#,
            );
            let plan = wbe_plan_new(request.as_ptr());
            assert!(!plan.is_null(), "{}", last_error());
            let result = wbe_plan_compile_target(plan, 0, c("[]").as_ptr());
            assert!(!result.is_null(), "{}", last_error());
            let stats = CStr::from_ptr(wbe_compile_stats_json(result))
                .to_str()
                .unwrap();
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(stats).unwrap()["admitted"]["list"],
                1
            );
            wbe_compile_free(result);
            assert!(wbe_plan_compile_target(plan, 1, c("[]").as_ptr()).is_null());
            assert!(last_error().contains("target index out of bounds"));
            wbe_plan_free(plan);
        }
    }

    #[test]
    fn plan_compiles_targets_concurrently() {
        unsafe {
            let request = c(
                r#"{"safari":[18,0],"lists":[{"id":"list","text":"||example.com^"}],"targets":[{"slot":1,"lists":[{"list":0}]},{"slot":2,"lists":[{"list":0}]}]}"#,
            );
            let plan = wbe_plan_new(request.as_ptr());
            assert!(!plan.is_null(), "{}", last_error());
            let shared = &*plan;
            std::thread::scope(|scope| {
                for target in 0..2 {
                    scope.spawn(move || {
                        let result = wbe_plan_compile_target(shared, target, c("[]").as_ptr());
                        assert!(!result.is_null(), "{}", last_error());
                        let stats = CStr::from_ptr(wbe_compile_stats_json(result))
                            .to_str()
                            .unwrap();
                        assert!(serde_json::from_str::<serde_json::Value>(stats).unwrap()
                            ["admitted"]
                            .is_object());
                        wbe_compile_free(result);
                    });
                }
            });
            wbe_plan_free(plan);
        }
    }
}
