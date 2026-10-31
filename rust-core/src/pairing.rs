//! Pairing: run an on-device RemotePairing "pairable host".
//!
//! A sideloaded app cannot ask the device to pair with a computer the way a Mac
//! does, because the pairing record is what grants access in the first place.
//! What *is* possible on iOS 27+ is the reverse direction: advertise ourselves
//! over Bonjour as a pairable host, and let the user approve us from
//! Settings > Privacy & Security > Developer Mode > Pair with <Host>.
//!
//! Flow:
//!   1. bind a TCP listener (port 0 = OS picks),
//!   2. hand the service id / port / TXT records to Swift via `ready_cb`, which
//!      publishes them with NetService,
//!   3. wait for the device to connect, drive the SRP handshake, surface the PIN
//!      through `pin_cb`,
//!   4. write the resulting RpPairingFile to `out_path`.
//!
//! The pairing file is what the tunnel code later uses for pair-verify.

use std::ffi::{c_char, c_void, CString};
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::ptr;

use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};
use tokio::net::TcpListener;

use crate::ffi_util::{cstr, opt_str};
use crate::logging;

pub type PairReadyCb = Option<
    extern "C" fn(
        ctx: *mut c_void,
        service_id: *const c_char,
        port: u16,
        txt_keys: *const *const c_char,
        txt_vals: *const *const c_char,
        txt_count: usize,
    ),
>;

pub type PairPinCb = Option<extern "C" fn(pin: *const c_char, ctx: *mut c_void)>;

/// Result of one pairing run. Free the strings with `mh_pairing_result_free`.
#[repr(C)]
pub struct MhPairResult {
    pub error: *mut c_char,
    pub device_name: *mut c_char,
    pub device_model: *mut c_char,
    pub device_udid: *mut c_char,
    pub pairing_file_path: *mut c_char,
    pub host_alt_irk_hex: *mut c_char,
}

impl MhPairResult {
    fn empty() -> Self {
        Self {
            error: ptr::null_mut(),
            device_name: ptr::null_mut(),
            device_model: ptr::null_mut(),
            device_udid: ptr::null_mut(),
            pairing_file_path: ptr::null_mut(),
            host_alt_irk_hex: ptr::null_mut(),
        }
    }
}

struct Callbacks {
    ready: PairReadyCb,
    pin: PairPinCb,
    ctx: *mut c_void,
}

// Raw pointers kept for the duration of a blocking call on a dedicated thread.
unsafe impl Send for Callbacks {}

pub unsafe fn run_host(
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
    if out.is_null() {
        return 2;
    }
    unsafe { *out = MhPairResult::empty() };

    let bind_addr = unsafe { opt_str(bind_addr, "0.0.0.0") };
    let name = unsafe { opt_str(name, "MetalHUD") };
    let model = unsafe { opt_str(model, "Mac17,7") };
    let out_path = unsafe { opt_str(out_path, "pairing.plist") };
    let saved_alt_irk = parse_alt_irk(&unsafe { opt_str(host_alt_irk_hex, "") });
    let cbs = Callbacks {
        ready: ready_cb,
        pin: pin_cb,
        ctx,
    };

    let res = crate::ffi_util::run_with_large_stack("mh_pairing", move || {
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => return Err(format!("tokio runtime: {e}")),
        };
        rt.block_on(run_host_async(
            bind_addr,
            port,
            name,
            model,
            out_path,
            saved_alt_irk,
            cbs,
        ))
    });

    match res {
        Ok(Ok((dev_name, dev_model, udid, path, irk))) => {
            unsafe {
                (*out).device_name = cstr(dev_name);
                (*out).device_model = cstr(dev_model);
                (*out).device_udid = cstr(udid);
                (*out).pairing_file_path = cstr(path);
                (*out).host_alt_irk_hex = cstr(irk);
            }
            0
        }
        Ok(Err(e)) => {
            unsafe { (*out).error = cstr(e) };
            1
        }
        Err(e) => {
            unsafe { (*out).error = cstr(e) };
            1
        }
    }
}

async fn run_host_async(
    bind_addr: String,
    port: u16,
    name: String,
    model: String,
    out_path: String,
    saved_alt_irk: Option<[u8; 16]>,
    cbs: Callbacks,
) -> Result<(String, String, String, String, String), String> {
    logging::Logger::new("pair").log(format!("binding {bind_addr}:{port}"));
    let ip: IpAddr = bind_addr
        .parse()
        .unwrap_or(IpAddr::V4(Ipv4Addr::UNSPECIFIED));
    let listener = TcpListener::bind(SocketAddr::new(ip, port))
        .await
        .map_err(|e| format!("cannot bind {bind_addr}:{port}: {e}"))?;
    let bound_port = listener
        .local_addr()
        .map_err(|e| format!("no local address: {e}"))?
        .port();
    logging::Logger::new("pair").log(format!("listening on port {bound_port}"));

    // Reuse the host key pair when we have one so an already-paired device still
    // recognises us after a reinstall.
    let mut pairing_file = match RpPairingFile::read_from_file(&out_path).await {
        Ok(mut existing) => {
            existing.alt_irk = None;
            logging::Logger::new("pair").log("reusing host identity from the existing file");
            existing
        }
        Err(_) => {
            logging::Logger::new("pair").log("generating a fresh host identity");
            RpPairingFile::generate(&name)
        }
    };

    let mut host_info = PairableHostInfo::generate(&name, &model);
    if let Some(irk) = saved_alt_irk {
        host_info.alt_irk = irk;
        logging::Logger::new("pair").log("reusing stored altIRK");
    }
    let host_alt_irk = host_info.alt_irk;
    let service_id = pairing_file.identifier.clone();

    emit_ready(&cbs, &service_id, bound_port, &host_info);

    logging::Logger::new("pair").log("waiting for the device to connect (open Settings)");
    let (stream, peer) = listener
        .accept()
        .await
        .map_err(|e| format!("accept failed: {e}"))?;
    logging::Logger::new("pair").log(format!("device connected from {peer}"));

    let socket = RpPairingSocket::new_device(stream);
    let mut host = PairableHost::new(socket, host_info);

    let pin_cb = cbs.pin;
    let pin_ctx = cbs.ctx;

    let peer_info = host
        .accept(&mut pairing_file, move |pin| {
            let pin_cb = pin_cb;
            let pin_ctx = pin_ctx;
            async move {
                logging::Logger::new("pair").log(format!("PIN issued: {pin}"));
                if let Some(cb) = pin_cb {
                    if let Ok(c) = CString::new(pin.as_str()) {
                        cb(c.as_ptr(), pin_ctx);
                    }
                }
            }
        })
        .await
        .map_err(|e| format!("pairing failed: {e}"))?;

    logging::Logger::new("pair").log(format!(
        "handshake complete with {} ({})",
        peer_info.name, peer_info.model
    ));

    pairing_file
        .write_to_file(&out_path)
        .await
        .map_err(|e| format!("cannot write {out_path}: {e}"))?;

    let size = tokio::fs::metadata(&out_path)
        .await
        .map(|m| m.len())
        .unwrap_or(0);
    if size == 0 {
        return Err(format!(
            "handshake finished but {out_path} is empty - approve the pairing on the device and retry"
        ));
    }
    logging::Logger::new("pair").log(format!("pairing file written ({size} bytes)"));

    Ok((
        peer_info.name,
        peer_info.model,
        peer_info.remotepairing_udid,
        out_path,
        bytes_to_hex(&host_alt_irk),
    ))
}

pub unsafe fn result_free(r: *mut MhPairResult) {
    if r.is_null() {
        return;
    }
    unsafe {
        for p in [
            (*r).error,
            (*r).device_name,
            (*r).device_model,
            (*r).device_udid,
            (*r).pairing_file_path,
            (*r).host_alt_irk_hex,
        ] {
            crate::ffi_util::string_free(p);
        }
        *r = MhPairResult::empty();
    }
}

fn emit_ready(cbs: &Callbacks, service_id: &str, port: u16, host_info: &PairableHostInfo) {
    let Some(cb) = cbs.ready else { return };
    let records = host_info.mdns_txt_records(service_id);
    let keys: Vec<CString> = records
        .iter()
        .map(|(k, _)| CString::new(k.as_str()).unwrap_or_default())
        .collect();
    let vals: Vec<CString> = records
        .iter()
        .map(|(_, v)| CString::new(v.as_str()).unwrap_or_default())
        .collect();
    let key_ptrs: Vec<*const c_char> = keys.iter().map(|s| s.as_ptr()).collect();
    let val_ptrs: Vec<*const c_char> = vals.iter().map(|s| s.as_ptr()).collect();

    let Ok(id_c) = CString::new(service_id) else {
        return;
    };
    cb(
        cbs.ctx,
        id_c.as_ptr(),
        port,
        key_ptrs.as_ptr(),
        val_ptrs.as_ptr(),
        records.len(),
    );
}

fn parse_alt_irk(s: &str) -> Option<[u8; 16]> {
    if s.len() != 32 {
        return None;
    }
    let mut out = [0u8; 16];
    for (i, b) in out.iter_mut().enumerate() {
        *b = u8::from_str_radix(s.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(out)
}

fn bytes_to_hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
