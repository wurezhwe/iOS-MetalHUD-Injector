//! C ABI for the iOS app.
//!
//! Everything here is synchronous from the caller's point of view: each entry
//! point blocks its own detached thread and reports progress through the log
//! callback installed by `mh_log_init`. That keeps the Swift side simple - call
//! from `Task.detached`, read the returned JSON (or error string).

use std::ffi::{c_char, c_void};
use std::net::IpAddr;

use crate::ffi_util::{cstr, opt_str, string_free};
use crate::logging;
use crate::pairing::{self, MhPairResult, PairPinCb, PairReadyCb};

/// Convert a Rust list of apps into the JSON the Swift side decodes.
fn apps_to_json(apps: &[crate::launch::AppInfo]) -> String {
    let mut out = String::from("[");
    for (i, app) in apps.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!(
            "{{\"bundleId\":{},\"name\":{},\"version\":{},\"developer\":{}}}",
            json_string(&app.bundle_id),
            json_string(&app.name),
            json_string(&app.version),
            app.developer
        ));
    }
    out.push(']');
    out
}

fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Helper: run a blocking operation on a big-stack thread and marshal the result
/// into (return_code, out_string) with an optional error string.
fn run_blocking<F>(tag: &'static str, out: *mut *mut c_char, err: *mut *mut c_char, f: F) -> i32
where
    F: FnOnce() -> Result<String, String> + Send + 'static,
{
    let joined: Result<Result<String, String>, String> =
        crate::ffi_util::run_with_large_stack(tag, f);

    match joined {
        Ok(Ok(msg)) => {
            if !out.is_null() {
                unsafe { *out = cstr(msg) };
            }
            0
        }
        Ok(Err(e)) => {
            logging::Logger::new(tag).log(format!("failed: {e}"));
            if !err.is_null() {
                unsafe { *err = cstr(e) };
            }
            1
        }
        Err(e) => {
            logging::Logger::new(tag).log(format!("thread failure: {e}"));
            if !err.is_null() {
                unsafe { *err = cstr(e) };
            }
            1
        }
    }
}

// ---------------------------------------------------------------------------
// Housekeeping
// ---------------------------------------------------------------------------

/// Install the log callback. Returns 0 on the first call, 1 afterwards.
#[no_mangle]
pub extern "C" fn mh_log_init(cb: logging::LogCallback, ctx: *mut c_void) -> i32 {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .try_init();
    logging::init(cb, ctx)
}

/// Free a string produced by this library.
#[no_mangle]
pub unsafe extern "C" fn mh_string_free(p: *mut c_char) {
    unsafe { string_free(p) };
}

/// Version string, handy when the app and the library drift apart.
#[no_mangle]
pub extern "C" fn mh_version() -> *mut c_char {
    cstr(env!("CARGO_PKG_VERSION"))
}

/// Set the candidate gateway addresses used for the RSD dial.
///
/// `hosts` is an array of `count` C strings of IPv4/IPv6 literals. An empty list
/// falls back to the built-in LocalDevVPN defaults.
#[no_mangle]
pub unsafe extern "C" fn mh_set_hosts(hosts: *const *const c_char, count: usize) -> i32 {
    let mut parsed: Vec<IpAddr> = Vec::new();
    if !hosts.is_null() {
        for i in 0..count {
            let p = unsafe { *hosts.add(i) };
            if p.is_null() {
                continue;
            }
            let text = unsafe { opt_str(p, "") };
            match text.parse::<IpAddr>() {
                Ok(ip) => {
                    if !parsed.contains(&ip) {
                        parsed.push(ip);
                    }
                }
                Err(_) => logging::Logger::new("hosts")
                    .log(format!("ignoring unparseable host '{text}'")),
            }
        }
    }
    logging::Logger::new("hosts").log(format!(
        "candidate gateways: {}",
        parsed
            .iter()
            .map(|h| h.to_string())
            .collect::<Vec<_>>()
            .join(", ")
    ));
    crate::tunnel::set_hosts(parsed);
    0
}

/// Forget the cached route (call after changing the VPN).
#[no_mangle]
pub extern "C" fn mh_clear_route() {
    crate::tunnel::clear_cache();
}

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------

/// Run the RemotePairing host until the device pairs or an error occurs.
///
/// Blocks. Call from a background queue. `out` receives the pairing file path on
/// success; free its strings with `mh_pairing_result_free`.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn mh_pairing_run_host(
    bind_addr: *const c_char,
    port: u16,
    name: *const c_char,
    model: *const c_char,
    out_path: *const c_char,
    host_alt_irk_hex: *const c_char,
    ready_cb: PairReadyCb,
    pin_cb: PairPinCb,
    ctx: *mut c_void,
    out: *mut MhPairResult,
) -> i32 {
    unsafe {
        pairing::run_host(
            bind_addr,
            port,
            name,
            model,
            out_path,
            host_alt_irk_hex,
            ready_cb,
            pin_cb,
            ctx,
            out,
        )
    }
}

/// Free the strings inside a `MhPairResult`.
#[no_mangle]
pub unsafe extern "C" fn mh_pairing_result_free(r: *mut MhPairResult) {
    unsafe { pairing::result_free(r) };
}

// ---------------------------------------------------------------------------
// Device queries
// ---------------------------------------------------------------------------

/// List installed applications. On success `out` receives a JSON array of
/// `{bundleId, name, version, developer}`.
#[no_mangle]
pub unsafe extern "C" fn mh_list_apps(
    pairing_path: *const c_char,
    out: *mut *mut c_char,
    err: *mut *mut c_char,
) -> i32 {
    let path = unsafe { opt_str(pairing_path, "") };
    run_blocking("list", out, err, move || {
        if path.is_empty() {
            return Err("no pairing file path given".to_string());
        }
        let apps = run_async(crate::launch::list_apps(&path))?;
        Ok(apps_to_json(&apps))
    })
}

/// Quick reachability probe: opens a tunnel and reports the device's RSD info.
#[no_mangle]
pub unsafe extern "C" fn mh_probe_device(
    pairing_path: *const c_char,
    out: *mut *mut c_char,
    err: *mut *mut c_char,
) -> i32 {
    let path = unsafe { opt_str(pairing_path, "") };
    run_blocking("probe", out, err, move || {
        if path.is_empty() {
            return Err("no pairing file path given".to_string());
        }
        run_async(async move {
            let link = crate::tunnel::connect(&path).await?;
            let mut names: Vec<String> = link.handshake.services.keys().cloned().collect();
            names.sort();
            let has_appservice = names
                .iter()
                .any(|n| n == "com.apple.coredevice.appservice");
            let has_dvt = names
                .iter()
                .any(|n| n == "com.apple.instruments.dtservicehub");
            Ok(format!(
                "{{\"host\":{},\"services\":{},\"appService\":{},\"dvt\":{}}}",
                json_string(&link.host.to_string()),
                names.len(),
                has_appservice,
                has_dvt
            ))
        })
    })
}

/// Launch an app with Metal HUD injected.
///
/// `env_json` is a JSON object of extra environment variables (may be NULL);
/// `args_json` is a JSON array of launch arguments (may be NULL).
#[no_mangle]
pub unsafe extern "C" fn mh_launch_app(
    pairing_path: *const c_char,
    bundle_id: *const c_char,
    env_json: *const c_char,
    args_json: *const c_char,
    kill_existing: bool,
    out: *mut *mut c_char,
    err: *mut *mut c_char,
) -> i32 {
    let path = unsafe { opt_str(pairing_path, "") };
    let bundle = unsafe { opt_str(bundle_id, "") };
    let env_raw = unsafe { opt_str(env_json, "") };
    let args_raw = unsafe { opt_str(args_json, "") };

    run_blocking("launch", out, err, move || {
        if path.is_empty() {
            return Err("no pairing file path given".to_string());
        }
        if bundle.is_empty() {
            return Err("no bundle id given".to_string());
        }

        let env = parse_env_json(&env_raw);
        let arguments = parse_args_json(&args_raw);

        let options = crate::launch::LaunchOptions {
            bundle_id: bundle,
            env,
            arguments,
            kill_existing,
        };
        run_async(crate::launch::launch(&path, &options))
    })
}

/// Save a PNG screenshot of the device screen.
#[no_mangle]
pub unsafe extern "C" fn mh_screenshot(
    pairing_path: *const c_char,
    out_path: *const c_char,
    out: *mut *mut c_char,
    err: *mut *mut c_char,
) -> i32 {
    let path = unsafe { opt_str(pairing_path, "") };
    let dest = unsafe { opt_str(out_path, "") };
    run_blocking("shot", out, err, move || {
        if path.is_empty() {
            return Err("no pairing file path given".to_string());
        }
        if dest.is_empty() {
            return Err("no destination path given".to_string());
        }
        run_async(crate::launch::screenshot(&path, &dest))
    })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a single-threaded runtime and run one future to completion.
fn run_async<F, T>(fut: F) -> Result<T, String>
where
    F: std::future::Future<Output = Result<T, String>>,
{
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("tokio runtime: {e}"))?;
    rt.block_on(fut)
}

/// Minimal `{"k":"v"}` parser - avoids pulling serde into the FFI surface.
fn parse_env_json(raw: &str) -> Vec<(String, String)> {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed == "null" {
        return Vec::new();
    }
    let body = trimmed
        .strip_prefix('{')
        .and_then(|s| s.strip_suffix('}'))
        .unwrap_or(trimmed);
    let mut out = Vec::new();
    for entry in split_top_level(body, ',') {
        let pair = split_top_level(&entry, ':');
        if pair.len() != 2 {
            continue;
        }
        let k = unquote(&pair[0]);
        let v = unquote(&pair[1]);
        if !k.is_empty() {
            out.push((k, v));
        }
    }
    out
}

/// Minimal `["a","b"]` parser.
fn parse_args_json(raw: &str) -> Vec<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed == "null" {
        return Vec::new();
    }
    let body = trimmed
        .strip_prefix('[')
        .and_then(|s| s.strip_suffix(']'))
        .unwrap_or(trimmed);
    split_top_level(body, ',')
        .into_iter()
        .map(|s| unquote(&s))
        .filter(|s| !s.is_empty())
        .collect()
}

fn split_top_level(input: &str, sep: char) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    let mut in_string = false;
    let mut escaped = false;
    for ch in input.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        match ch {
            '\\' if in_string => {
                current.push(ch);
                escaped = true;
            }
            '"' => {
                in_string = !in_string;
                current.push(ch);
            }
            c if c == sep && !in_string => {
                parts.push(current.trim().to_string());
                current = String::new();
            }
            c => current.push(c),
        }
    }
    if !current.trim().is_empty() {
        parts.push(current.trim().to_string());
    }
    parts
}

fn unquote(raw: &str) -> String {
    let trimmed = raw.trim();
    let inner = trimmed
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .unwrap_or(trimmed);
    let mut out = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('r') => out.push('\r'),
            Some('t') => out.push('\t'),
            Some(other) => out.push(other),
            None => {}
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_env_object() {
        let env = parse_env_json(r#"{"MTL_HUD_ENABLED":"1","MTL_HUD_SCALE":"0.35"}"#);
        assert_eq!(env.len(), 2);
        assert_eq!(env[0], ("MTL_HUD_ENABLED".into(), "1".into()));
        assert_eq!(env[1], ("MTL_HUD_SCALE".into(), "0.35".into()));
    }

    #[test]
    fn parses_args_array() {
        assert_eq!(parse_args_json(r#"["-a","b c"]"#), vec!["-a", "b c"]);
        assert!(parse_args_json("").is_empty());
        assert!(parse_args_json("null").is_empty());
    }

    #[test]
    fn escapes_json_strings() {
        assert_eq!(json_string("a\"b"), "\"a\\\"b\"");
        assert_eq!(apps_to_json(&[]), "[]");
    }
}
