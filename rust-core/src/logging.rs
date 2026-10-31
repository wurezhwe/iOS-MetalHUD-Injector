//! Logging bridge: every interesting step is mirrored to a C callback so the
//! SwiftUI side can show a live console while a launch is being set up.

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::OnceLock;

pub type LogCallback = Option<extern "C" fn(ctx: *mut c_void, msg: *const c_char)>;

struct Sink {
    cb: LogCallback,
    ctx: *mut c_void,
}

// The sink is only ever read after `init` stores it, and callbacks are plain C
// function pointers with an opaque user context, so moving it across threads is
// sound as long as the Swift side keeps the context alive (it does: the context
// is a retained class instance for the lifetime of the operation).
unsafe impl Send for Sink {}
unsafe impl Sync for Sink {}

static SINK: OnceLock<Sink> = OnceLock::new();

/// Install the callback once per process. Returns 0 on the first call.
pub fn init(cb: LogCallback, ctx: *mut c_void) -> i32 {
    let first = SINK.get().is_none();
    let _ = SINK.set(Sink { cb, ctx });
    if first {
        0
    } else {
        1
    }
}

/// Emit one line of log output.
pub fn log(line: impl AsRef<str>) {
    let text = line.as_ref();
    tracing::info!("{text}");
    if let Some(sink) = SINK.get() {
        if let Some(cb) = sink.cb {
            if let Ok(c) = CString::new(text) {
                cb(sink.ctx, c.as_ptr());
            }
        }
    }
}

/// A per-operation logger that prefixes every line with a short tag.
#[derive(Clone, Copy)]
pub struct Logger {
    pub tag: &'static str,
}

impl Logger {
    pub const fn new(tag: &'static str) -> Self {
        Self { tag }
    }

    pub fn log(&self, msg: impl AsRef<str>) {
        log(format!("[{}] {}", self.tag, msg.as_ref()));
    }
}

/// Helper used by the C entry points to turn a `*const c_char` log argument into
/// something we can format.
pub unsafe fn cstr_lossy(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned()
    }
}
