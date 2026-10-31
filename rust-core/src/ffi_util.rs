//! Small FFI helpers: C string handling and a big-stack thread runner.
//!
//! The tunnel stack is futures-heavy and recurses through io::copy style loops
//! on the async side, but the *drop* of the whole connection tree happens on the
//! thread that owns it. Running the blocking entry points on a thread with a
//! large stack keeps deep deallocations from overflowing the 512 KB default
//! secondary thread stack.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Read a C string, falling back to `default` for NULL or invalid UTF-8.
pub unsafe fn opt_str(ptr: *const c_char, default: &str) -> String {
    if ptr.is_null() {
        return default.to_string();
    }
    match unsafe { CStr::from_ptr(ptr) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => default.to_string(),
    }
}

/// Allocate a heap C string the caller frees with `mh_string_free`.
pub fn cstr(value: impl Into<String>) -> *mut c_char {
    let value = value.into();
    match CString::new(value) {
        Ok(c) => c.into_raw(),
        // Interior NULs cannot cross the boundary; drop them instead of failing.
        Err(e) => {
            let cleaned = e
                .into_vec()
                .into_iter()
                .filter(|b| *b != 0)
                .collect::<Vec<u8>>();
            CString::new(cleaned)
                .map(|c| c.into_raw())
                .unwrap_or(std::ptr::null_mut())
        }
    }
}

/// Free a string produced by [`cstr`].
pub unsafe fn string_free(p: *mut c_char) {
    if !p.is_null() {
        drop(unsafe { CString::from_raw(p) });
    }
}

/// Run `f` on a worker thread with a generous stack, returning its result.
pub fn run_with_large_stack<F, R>(name: &str, f: F) -> Result<R, String>
where
    F: FnOnce() -> R + Send + 'static,
    R: Send + 'static,
{
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    let thread_name = name.to_string();
    let spawned = std::thread::Builder::new()
        .name(thread_name)
        .stack_size(32 * 1024 * 1024)
        .spawn(move || {
            let out = f();
            let _ = tx.send(out);
        });

    match spawned {
        Ok(handle) => {
            let result = rx.recv();
            let _ = handle.join();
            result.map_err(|_| "worker thread dropped before returning".to_string())
        }
        Err(e) => Err(format!("could not spawn worker thread: {e}")),
    }
}
