//! Device tunnel: RemotePairing -> TLS-PSK -> CDTunnel -> userspace TCP -> RSD.
//!
//! Why this shape:
//!
//! * The app runs **on** the device, so there is no USB link to use. The only way
//!   to reach the CoreDevice/instruments services is the loopback tunnel that a
//!   VPN app (LocalDevVPN, SideStore's WireGuard, ...) exposes, which forwards
//!   `10.7.0.1:49152` to the device's own RSD listener.
//! * RSD at 49152 only speaks RemoteXPC. Pairing over it yields an RPPairing
//!   client, which can ask the device to `createListener`; the device then opens
//!   an ephemeral TLS-PSK tunnel port.
//! * `createListener` returns a port but no host, so the host has to be guessed;
//!   we sweep the addresses Swift handed us (`mh_set_hosts`).
//! * Inside the tunnel the device has a second RSD endpoint on
//!   `serverRSDPort`, which is where the real services live.
//!
//! Deliberately never dials 127.0.0.1: on iOS that makes
//! `remotepairingdeviced` invalidate the control channel and drop all further
//! network connections until Developer Mode is toggled.

use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::time::Duration;

use idevice::remote_pairing::{
    connect_tls_psk_tunnel_native, RemotePairingClient, RpPairingFile, RpPairingSocket,
    RpPairingSocketProvider,
};
use idevice::services::rsd::RsdHandshake;
use idevice::tcp::adapter::Adapter;
use idevice::tcp::handle::AdapterHandle;
use idevice::{ReadWrite, RemoteXpcClient, RsdService};
use tokio::net::TcpStream;

use crate::logging::Logger;

const LOG: Logger = Logger::new("tunnel");

/// RSD listener the loopback VPN forwards.
const RSD_PORT: u16 = 49152;
/// Tunnel service advertised inside the first RSD handshake.
const TUNNEL_SERVICE: &str = "com.apple.internal.dt.coredevice.untrusted.tunnelservice";
/// How long a single candidate host may take to accept a TCP connection.
const DIAL_TIMEOUT: Duration = Duration::from_millis(800);
/// Hosts are reconsidered this many times before we give up.
const DIAL_ROUNDS: u32 = 4;

static HOSTS: Mutex<Vec<IpAddr>> = Mutex::new(Vec::new());

/// Where a tunnel was last established. Re-probing all hosts on every call is
/// slow, and a wrong guess only costs one refused connect.
#[derive(Clone, Copy)]
struct CachedRoute {
    host: IpAddr,
    via_remotexpc: bool,
}

static CACHED: Mutex<Option<CachedRoute>> = Mutex::new(None);

pub fn set_hosts(hosts: Vec<IpAddr>) {
    if let Ok(mut guard) = HOSTS.lock() {
        *guard = hosts;
    }
    clear_cache();
}

pub fn clear_cache() {
    if let Ok(mut guard) = CACHED.lock() {
        *guard = None;
    }
}

fn cached_route() -> Option<CachedRoute> {
    CACHED.lock().ok().and_then(|g| *g)
}

fn store_route(route: CachedRoute) {
    if let Ok(mut guard) = CACHED.lock() {
        *guard = Some(route);
    }
}

/// Hosts to try, best first. Loopback is filtered out on purpose (see module doc).
fn candidates() -> Vec<IpAddr> {
    fn push(out: &mut Vec<IpAddr>, ip: IpAddr) {
        if !ip.is_loopback() && !out.contains(&ip) {
            out.push(ip);
        }
    }

    let mut out: Vec<IpAddr> = Vec::new();
    if let Some(route) = cached_route() {
        push(&mut out, route.host);
    }
    if let Ok(guard) = HOSTS.lock() {
        for ip in guard.iter() {
            push(&mut out, *ip);
        }
    }
    // LocalDevVPN / SideStore WireGuard defaults.
    for fb in ["10.7.0.1", "10.7.0.2", "10.7.0.3", "10.0.0.1", "172.16.0.1"] {
        if let Ok(ip) = fb.parse::<IpAddr>() {
            push(&mut out, ip);
        }
    }
    out
}

/// A live connection to the device's RSD, plus the userspace TCP adapter behind
/// it. Dropping this tears the whole stack down.
pub struct DeviceLink {
    pub adapter: AdapterHandle,
    pub handshake: RsdHandshake,
    pub host: IpAddr,
}

impl DeviceLink {
    /// Open one RSD service. The split borrow inside makes it possible to hand
    /// the adapter to a handshake that we also hold mutably.
    pub async fn open<T>(&mut self) -> Result<T, String>
    where
        T: RsdService,
    {
        let DeviceLink {
            adapter, handshake, ..
        } = self;
        handshake
            .connect::<T>(adapter)
            .await
            .map_err(|e| format!("{}: {e}", T::rsd_service_name()))
    }
}

/// Establish a tunnel and complete an RSD handshake inside it.
pub async fn connect(pairing_path: &str) -> Result<DeviceLink, String> {
    let pairing_file = RpPairingFile::read_from_file(pairing_path)
        .await
        .map_err(|e| format!("cannot read pairing file '{pairing_path}': {e}"))?;

    let hosts = candidates();
    if hosts.is_empty() {
        return Err("no candidate host addresses; set the device IP first".into());
    }
    LOG.log(format!(
        "trying {} host(s): {}",
        hosts.len(),
        hosts
            .iter()
            .map(|h| h.to_string())
            .collect::<Vec<_>>()
            .join(", ")
    ));

    let cached = cached_route();
    let mut failures: Vec<String> = Vec::new();

    for host in hosts {
        let prefer_remotexpc = cached.map(|c| c.via_remotexpc).unwrap_or(true);

        if prefer_remotexpc {
            match try_host(host, &pairing_file, true).await {
                Ok(link) => {
                    store_route(CachedRoute {
                        host,
                        via_remotexpc: true,
                    });
                    return Ok(link);
                }
                Err(e) => {
                    LOG.log(format!("{host}:{RSD_PORT} RemoteXPC failed: {e}"));
                    failures.push(format!("{host} RemoteXPC: {e}"));
                }
            }
        }

        match try_host(host, &pairing_file, false).await {
            Ok(link) => {
                store_route(CachedRoute {
                    host,
                    via_remotexpc: false,
                });
                return Ok(link);
            }
            Err(e) => {
                LOG.log(format!("{host}:{RSD_PORT} raw RPPairing failed: {e}"));
                failures.push(format!("{host} raw RPPairing: {e}"));
            }
        }
    }

    let last_error = if failures.is_empty() {
        "no candidate host was tried".to_string()
    } else {
        failures.last().cloned().unwrap_or_default()
    };

    Err(format!(
        "could not reach the device: {last_error}. \
         Make sure a loopback VPN (LocalDevVPN or SideStore WireGuard) is running, \
         and that its gateway address is one of the hosts tried above."
    ))
}

async fn try_host(
    host: IpAddr,
    pairing_file: &RpPairingFile,
    via_remotexpc: bool,
) -> Result<DeviceLink, String> {
    let addr = SocketAddr::new(host, RSD_PORT);
    LOG.log(format!(
        "connecting to RSD at {addr} ({})",
        if via_remotexpc {
            "RemoteXPC"
        } else {
            "raw RPPairing"
        }
    ));

    let mut pairing_file = pairing_file.clone();
    let stream = tokio::time::timeout(DIAL_TIMEOUT, TcpStream::connect(addr))
        .await
        .map_err(|_| "connect timed out".to_string())?
        .map_err(|e| format!("connect failed: {e}"))?;

    // --- pair-verify over the chosen transport -----------------------------
    // The two transports give different concrete types, so each branch hands
    // its client to the same generic continuation instead of being unified into
    // one `if` expression.
    if via_remotexpc {
        let rsd = RsdHandshake::new(stream)
            .await
            .map_err(|e| format!("RSD handshake failed: {e}"))?;
        let service = rsd
            .services
            .get(TUNNEL_SERVICE)
            .ok_or_else(|| format!("device does not advertise {TUNNEL_SERVICE}"))?
            .port;
        let service_addr = SocketAddr::new(host, service);
        LOG.log(format!("opening the tunnel service at {service_addr}"));

        let tunnel_stream = tokio::time::timeout(DIAL_TIMEOUT, TcpStream::connect(service_addr))
            .await
            .map_err(|_| "tunnel-service connect timed out".to_string())?
            .map_err(|e| format!("tunnel-service connect failed: {e}"))?;

        let mut conn = RemoteXpcClient::new(tunnel_stream)
            .await
            .map_err(|e| format!("RemoteXPC handshake failed: {e}"))?;
        conn.do_handshake()
            .await
            .map_err(|e| format!("RemoteXPC do_handshake failed: {e}"))?;
        let _ = conn
            .recv_root()
            .await
            .map_err(|e| format!("RemoteXPC recv_root failed: {e}"))?;

        finish_tunnel(
            RemotePairingClient::new(conn, "MetalHUD"),
            host,
            &mut pairing_file,
        )
        .await
    } else {
        finish_tunnel(
            RemotePairingClient::new(RpPairingSocket::new(stream), "MetalHUD"),
            host,
            &mut pairing_file,
        )
        .await
    }
}

/// Everything after pair-verify, shared by both transports.
async fn finish_tunnel<R>(
    mut rpc: RemotePairingClient<R>,
    host: IpAddr,
    pairing_file: &mut RpPairingFile,
) -> Result<DeviceLink, String>
where
    R: RpPairingSocketProvider,
{
    rpc.connect(pairing_file, || async { "000000".to_string() })
        .await
        .map_err(|e| {
            format!(
                "pair-verify rejected ({e}). The pairing file no longer matches this \
                 device; pair again from Settings > Privacy & Security > Developer Mode"
            )
        })?;
    LOG.log("pair-verify succeeded");

    // --- ask the device for a tunnel listener ------------------------------
    let mut tunnel_port = rpc
        .create_tcp_listener()
        .await
        .map_err(|e| format!("createListener failed: {e}"))?;
    LOG.log(format!("device opened tunnel port {tunnel_port}"));

    // createListener names a port but not a host, so sweep the candidates.
    let mut last = String::from("no host answered on the tunnel port");
    for round in 1..=DIAL_ROUNDS {
        let sweep_hosts: Vec<IpAddr> = {
            let mut v = vec![host];
            if let Ok(guard) = HOSTS.lock() {
                for ip in guard.iter() {
                    if !ip.is_loopback() && !v.contains(ip) {
                        v.push(*ip);
                    }
                }
            }
            v
        };

        for cand in sweep_hosts {
            let addr = SocketAddr::new(cand, tunnel_port);
            let stream = match tokio::time::timeout(DIAL_TIMEOUT, TcpStream::connect(addr)).await {
                Ok(Ok(s)) => s,
                Ok(Err(e)) => {
                    last = format!("{addr}: {e}");
                    continue;
                }
                Err(_) => {
                    last = format!("{addr}: timed out");
                    continue;
                }
            };

            let key = rpc.encryption_key().to_vec();
            match connect_tls_psk_tunnel_native(stream, &key).await {
                Ok(tunnel) => {
                    LOG.log(format!("tunnel up via {addr}"));
                    return build_link(tunnel, cand).await;
                }
                Err(e) => {
                    LOG.log(format!("{addr}: TLS-PSK/CDTunnel handshake failed: {e}"));
                    last = format!("{addr}: TLS-PSK handshake failed: {e}");
                    // That connection consumed the listener; ask for a fresh one.
                    match rpc.create_tcp_listener().await {
                        Ok(port) => tunnel_port = port,
                        Err(e) => return Err(format!("createListener retry failed: {e}")),
                    }
                }
            }
        }

        if round < DIAL_ROUNDS {
            tokio::time::sleep(Duration::from_millis(700)).await;
        }
    }

    Err(format!(
        "the device never accepted a tunnel connection ({last}). A loopback VPN that \
         forwards RSD but not ephemeral ports looks exactly like this."
    ))
}

async fn build_link<S: ReadWrite + 'static>(
    tunnel: idevice::tunnel::CdTunnel<S>,
    host: IpAddr,
) -> Result<DeviceLink, String> {
    let client_ip: IpAddr = tunnel
        .info
        .client_address
        .parse()
        .map_err(|e| format!("bad client address '{}': {e}", tunnel.info.client_address))?;
    let server_ip: IpAddr = tunnel
        .info
        .server_address
        .parse()
        .map_err(|e| format!("bad server address '{}': {e}", tunnel.info.server_address))?;
    let mtu = tunnel.info.mtu as usize;
    let rsd_port = tunnel.info.server_rsd_port;

    let raw = tunnel.into_inner();
    let mut adapter = Adapter::new(Box::new(raw), client_ip, server_ip);
    adapter.set_mss(mtu.saturating_sub(60));
    let mut adapter = adapter.to_async_handle();

    LOG.log(format!(
        "inside the tunnel: client {client_ip}, device {server_ip}, mtu {mtu}; \
         dialling RSD on port {rsd_port}"
    ));

    let stream = tokio::time::timeout(Duration::from_secs(15), adapter.connect(rsd_port))
        .await
        .map_err(|_| format!("RSD connect on port {rsd_port} timed out"))?
        .map_err(|e| format!("RSD connect on port {rsd_port} failed: {e}"))?;

    let handshake = RsdHandshake::new(stream)
        .await
        .map_err(|e| format!("RSD handshake inside the tunnel failed: {e}"))?;

    LOG.log(format!(
        "RSD handshake complete, {} service(s) advertised",
        handshake.services.len()
    ));

    Ok(DeviceLink {
        adapter,
        handshake,
        host,
    })
}
