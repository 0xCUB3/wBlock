//! `wbe compile [--safari 18.0] [--trusted] [--runtime-out FILE] LIST...`
//! writes Safari JSON to stdout and stats JSON to stderr.

use std::time::Instant;
use wbe::webkit::{to_json, SafariVersion};
use wbe::{compile, CompileOptions, ListInput};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("compile") => compile_cmd(&args[1..]),
        _ => {
            eprintln!("usage: wbe compile [--safari 18.0] [--trusted] [--runtime-out FILE] LIST...");
            std::process::exit(2);
        }
    }
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
