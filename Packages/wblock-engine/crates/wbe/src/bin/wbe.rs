//! `wbe compile [--safari 18.0] [--trusted] [--runtime-out FILE] LIST...`
//! writes Safari JSON to stdout and stats JSON to stderr.
//! `wbe engine-build --resources R --out FILE RUNTIME.txt` serializes a
//! runtime engine. `wbe lookup [--resources R] [--bench N] ENGINE URL...`
//! prints PagePayload JSON per URL; with `--bench` it prints p50/p99 JSON for
//! N lookups over the URLs in the file.

use std::time::Instant;
use wbe::runtime::Engine;
use wbe::webkit::{to_json, SafariVersion};
use wbe::{compile, CompileOptions, ListInput};

/// Used by `lookup` when `--resources` is not given.
const DEFAULT_RESOURCES: &str = include_str!("../../../../resources/resources.json");

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("compile") => compile_cmd(&args[1..]),
        Some("engine-build") => engine_build_cmd(&args[1..]),
        Some("lookup") => lookup_cmd(&args[1..]),
        _ => {
            eprintln!("usage: wbe compile [--safari 18.0] [--trusted] [--runtime-out FILE] LIST...");
            eprintln!("       wbe engine-build --resources R --out FILE RUNTIME.txt");
            eprintln!("       wbe lookup [--resources R] [--bench N] ENGINE URL|URLFILE...");
            std::process::exit(2);
        }
    }
}

fn read(path: &str) -> String {
    std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"))
}

fn engine_build_cmd(args: &[String]) {
    let mut resources = None;
    let mut out = None;
    let mut runtime = None;
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--resources" => resources = it.next().cloned(),
            "--out" => out = it.next().cloned(),
            _ => runtime = Some(arg.clone()),
        }
    }
    let (Some(resources), Some(out), Some(runtime)) = (resources, out, runtime) else {
        eprintln!("usage: wbe engine-build --resources R --out FILE RUNTIME.txt");
        std::process::exit(2);
    };
    let text = read(&runtime);
    let lines: Vec<String> = text.lines().map(str::to_owned).collect();

    let start = Instant::now();
    let engine = Engine::build(&lines, &read(&resources)).unwrap_or_else(|e| panic!("{e}"));
    let bytes = engine.serialize();
    let build_ms = start.elapsed().as_secs_f64() * 1000.0;

    std::fs::write(&out, &bytes).unwrap_or_else(|e| panic!("{out}: {e}"));
    let report =
        serde_json::json!({ "build_ms": build_ms, "bytes": bytes.len(), "lines": lines.len() });
    eprintln!("{report}");
}

fn lookup_cmd(args: &[String]) {
    let mut resources = None;
    let mut bench = None;
    let mut rest = Vec::new();
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--resources" => resources = it.next().cloned(),
            "--bench" => {
                bench = Some(
                    it.next()
                        .expect("--bench needs a count")
                        .parse::<usize>()
                        .expect("count"),
                )
            }
            _ => rest.push(arg.clone()),
        }
    }
    let Some((engine_path, inputs)) = rest.split_first() else {
        eprintln!("usage: wbe lookup [--resources R] [--bench N] ENGINE URL|URLFILE...");
        std::process::exit(2);
    };
    let resources_json = resources.map_or_else(|| DEFAULT_RESOURCES.to_owned(), |p| read(&p));

    let start = Instant::now();
    let bytes = std::fs::read(engine_path).unwrap_or_else(|e| panic!("{engine_path}: {e}"));
    let engine = Engine::deserialize(&bytes, &resources_json).unwrap_or_else(|e| panic!("{e}"));
    let load_ms = start.elapsed().as_secs_f64() * 1000.0;

    match bench {
        Some(n) => bench_cmd(&engine, load_ms, n, &read(&inputs[0])),
        None => {
            let mut timings = Vec::new();
            for url in inputs {
                let start = Instant::now();
                let payload = engine.lookup(url);
                timings.push(
                    serde_json::json!({ "url": url, "us": start.elapsed().as_secs_f64() * 1e6 }),
                );
                println!(
                    "{}",
                    serde_json::to_string(&payload).expect("payload serializes")
                );
            }
            eprintln!(
                "{}",
                serde_json::json!({ "load_ms": load_ms, "lookups": timings })
            );
        }
    }
}

fn bench_cmd(engine: &Engine, load_ms: f64, count: usize, url_text: &str) {
    let urls: Vec<&str> = url_text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    assert!(!urls.is_empty(), "URL file is empty");
    let mut us = Vec::with_capacity(count);
    for i in 0..count {
        let url = urls[i % urls.len()];
        let start = Instant::now();
        std::hint::black_box(engine.lookup(std::hint::black_box(url)));
        us.push(start.elapsed().as_secs_f64() * 1e6);
    }
    us.sort_by(f64::total_cmp);
    let pct = |p: usize| us[(us.len() * p / 100).min(us.len() - 1)];
    let mean = us.iter().sum::<f64>() / us.len() as f64;
    let report = serde_json::json!({
        "load_ms": load_ms,
        "lookups": count,
        "urls": urls.len(),
        "p50_us": pct(50),
        "p99_us": pct(99),
        "mean_us": mean,
    });
    println!("{report}");
}

fn compile_cmd(args: &[String]) {
    let mut safari = SafariVersion::new(18, 0);
    let mut trusted = false;
    let mut runtime_out = None;
    let mut paths = Vec::new();
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--safari" => {
                let v = it.next().expect("--safari needs a version");
                let (major, minor) = v.split_once('.').unwrap_or((v, "0"));
                safari = SafariVersion::new(major.parse().unwrap(), minor.parse().unwrap());
            }
            "--trusted" => trusted = true,
            "--runtime-out" => runtime_out = Some(it.next().expect("--runtime-out needs a path").clone()),
            _ => paths.push(arg.clone()),
        }
    }
    let texts: Vec<String> = paths
        .iter()
        .map(|p| std::fs::read_to_string(p).unwrap_or_else(|e| panic!("{p}: {e}")))
        .collect();
    let inputs: Vec<ListInput> = texts.iter().map(|text| ListInput { text, trusted }).collect();

    let start = Instant::now();
    let out = compile(&inputs, &CompileOptions { safari });
    let compile_ms = start.elapsed().as_secs_f64() * 1000.0;

    print!("{}", to_json(&out.webkit));
    if let Some(path) = runtime_out {
        std::fs::write(path, out.runtime.join("\n")).expect("write runtime rules");
    }
    let stats = serde_json::json!({ "compile_ms": compile_ms, "stats": out.stats });
    eprintln!("{stats}");
}
