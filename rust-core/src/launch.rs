//! Listing apps and launching them with Metal HUD injected.
//!
//! The Developer-menu "Show Graphics HUD" switch only applies to processes that
//! carry `get-task-allow` (Xcode/debug builds and self-signed apps). App Store
//! apps do not, which is why the switch appears to do nothing for them.
//!
//! Metal, however, reads process environment variables when it initialises, and
//! that path never consults the code signature. The documented switches are:
//!
//! * `MTL_HUD_ENABLED`     - turns the HUD on
//! * `MTL_HUD_SCALE`       - HUD size, e.g. `0.35`
//! * `MTL_HUD_ALIGNMENT`   - e.g. `top-right`, `bottom-left`
//! * `MTL_HUD_LOG_ENABLED` - mirrors HUD data to the log
//!
//! CoreDevice's `launchapplication` feature takes an `environmentVariables`
//! dictionary, so we can hand them to any installed app - App Store or not.
//!
//! Two launch paths are tried, in order:
//!   1. `com.apple.coredevice.appservice` (the one Xcode itself uses), and
//!   2. the DVT `processcontrol` service, for devices/builds where the
//!      coredevice app service is missing.

use idevice::services::core_device::AppServiceClient;
use idevice::services::dvt::process_control::ProcessControlClient;
use idevice::services::dvt::remote_server::RemoteServerClient;
use idevice::services::installation_proxy::InstallationProxyClient;
use idevice::ReadWrite;
use plist::Dictionary;

use crate::logging::Logger;
use crate::tunnel::{self, DeviceLink};

const LOG: Logger = Logger::new("launch");

#[derive(Debug, Clone)]
pub struct AppInfo {
    pub bundle_id: String,
    pub name: String,
    pub version: String,
    pub developer: bool,
}

#[derive(Debug, Clone)]
pub struct LaunchOptions {
    pub bundle_id: String,
    pub env: Vec<(String, String)>,
    pub arguments: Vec<String>,
    pub kill_existing: bool,
}

impl LaunchOptions {
    /// Build the environment we want the target process to inherit.
    pub fn hud_env(
        scale: Option<String>,
        alignment: Option<String>,
        extra_log: bool,
    ) -> Vec<(String, String)> {
        let mut env = vec![("MTL_HUD_ENABLED".to_string(), "1".to_string())];
        if let Some(scale) = scale.filter(|s| !s.trim().is_empty()) {
            env.push(("MTL_HUD_SCALE".to_string(), scale));
        }
        if let Some(alignment) = alignment.filter(|s| !s.trim().is_empty()) {
            env.push(("MTL_HUD_ALIGNMENT".to_string(), alignment));
        }
        if extra_log {
            env.push(("MTL_HUD_LOG_ENABLED".to_string(), "1".to_string()));
        }
        env
    }
}

fn env_dict(env: &[(String, String)]) -> Dictionary {
    let mut dict = Dictionary::new();
    for (k, v) in env {
        dict.insert(k.clone(), plist::Value::String(v.clone()));
    }
    dict
}

fn args_dict(args: &[String]) -> Dictionary {
    let mut dict = Dictionary::new();
    for (i, a) in args.iter().enumerate() {
        dict.insert(i.to_string(), plist::Value::String(a.clone()));
    }
    dict
}

/// List installed applications.
///
/// Three sources, because which services exist depends on the OS build:
///   1. CoreDevice `appservice` - what Xcode uses on recent releases;
///   2. the DVT `applicationListing` channel, reached over
///      `com.apple.instruments.dtservicehub` (advertised on far more devices);
///   3. InstallationProxy, whose RSD shim is nearly universal.
pub async fn list_apps(pairing_path: &str) -> Result<Vec<AppInfo>, String> {
    let mut link = tunnel::connect(pairing_path).await?;

    let mut out = match list_via_dvt(&mut link).await {
        Ok(apps) => apps,
        Err(dvt_error) => {
            LOG.log(format!("DVT application listing failed: {dvt_error}"));
            match list_via_core_device(&mut link).await {
                Ok(apps) => apps,
                Err(core_error) => {
                    LOG.log(format!("CoreDevice appservice failed: {core_error}"));
                    list_via_installation_proxy(&mut link).await?
                }
            }
        }
    };

    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    out.dedup_by(|a, b| a.bundle_id == b.bundle_id);
    LOG.log(format!("{} installed app(s)", out.len()));
    Ok(out)
}

async fn list_via_core_device(link: &mut DeviceLink) -> Result<Vec<AppInfo>, String> {
    let entries = {
        let mut service: AppServiceClient<Box<dyn ReadWrite>> = link.open().await?;
        service
            .list_apps(false, true, false, false, false)
            .await
            .map_err(|e| format!("listapps failed: {e}"))?
    };

    Ok(entries
        .into_iter()
        .map(|a| AppInfo {
            bundle_id: a.bundle_identifier,
            name: a.name,
            version: a.version.or(a.bundle_version).unwrap_or_default(),
            developer: a.is_developer_app,
        })
        .filter(|a| !a.bundle_id.is_empty())
        .collect())
}

async fn list_via_dvt(link: &mut DeviceLink) -> Result<Vec<AppInfo>, String> {
    use idevice::services::dvt::application_listing::ApplicationListingClient;

    let mut server: RemoteServerClient<Box<dyn ReadWrite>> = link.open().await?;
    let entries = {
        let mut listing = ApplicationListingClient::new(&mut server)
            .await
            .map_err(|e| format!("applicationListing channel failed: {e}"))?;
        listing
            .installed_applications()
            .await
            .map_err(|e| format!("installedApplicationsMatching failed: {e}"))?
    };

    LOG.log(format!("DVT reported {} app bundle(s)", entries.len()));

    Ok(entries
        .into_iter()
        .filter_map(|entry| {
            let bundle_id = entry
                .get("CFBundleIdentifier")
                .and_then(|v| v.as_string())?
                .to_string();
            // DVT returns system daemons and app extensions too; only the
            // launchable user-facing apps are interesting here.
            let kind = entry
                .get("ApplicationType")
                .and_then(|v| v.as_string())
                .unwrap_or("User");
            if kind != "User" && kind != "System" {
                return None;
            }
            if entry
                .get("IsAppClip")
                .and_then(|v| v.as_boolean())
                .unwrap_or(false)
            {
                return None;
            }
            let name = entry
                .get("CFBundleDisplayName")
                .and_then(|v| v.as_string())
                .or_else(|| entry.get("CFBundleName").and_then(|v| v.as_string()))
                .unwrap_or(&bundle_id)
                .to_string();
            let version = entry
                .get("CFBundleShortVersionString")
                .and_then(|v| v.as_string())
                .unwrap_or_default()
                .to_string();
            Some(AppInfo {
                bundle_id,
                name,
                version,
                developer: false,
            })
        })
        .collect())
}

async fn list_via_installation_proxy(link: &mut DeviceLink) -> Result<Vec<AppInfo>, String> {
    let mut proxy: InstallationProxyClient = link.open().await?;
    let apps = proxy
        .get_apps(Some("User"), None)
        .await
        .map_err(|e| format!("InstallationProxy lookup failed: {e}"))?;

    Ok(apps
        .into_iter()
        .filter_map(|(bundle_id, value)| {
            let info = value.as_dictionary()?;
            let name = info
                .get("CFBundleDisplayName")
                .and_then(|v| v.as_string())
                .or_else(|| info.get("CFBundleName").and_then(|v| v.as_string()))
                .unwrap_or(&bundle_id)
                .to_string();
            let version = info
                .get("CFBundleShortVersionString")
                .and_then(|v| v.as_string())
                .unwrap_or_default()
                .to_string();
            Some(AppInfo {
                bundle_id,
                name,
                version,
                developer: false,
            })
        })
        .collect())
}

/// Launch `options.bundle_id`, injecting `options.env`.
pub async fn launch(pairing_path: &str, options: &LaunchOptions) -> Result<String, String> {
    let mut link = tunnel::connect(pairing_path).await?;

    for (k, v) in &options.env {
        LOG.log(format!("injecting {k}={v}"));
    }

    // DVT first: `dtservicehub` is advertised on far more OS builds than the
    // coredevice app service, and its processcontrol channel takes the same
    // environment dictionary.
    match launch_via_dvt(&mut link, options).await {
        Ok(msg) => return Ok(msg),
        Err(dvt_error) => {
            LOG.log(format!("DVT launch failed, trying CoreDevice: {dvt_error}"));
        }
    }

    launch_via_core_device(&mut link, options).await
}

async fn launch_via_core_device(
    link: &mut DeviceLink,
    options: &LaunchOptions,
) -> Result<String, String> {
    let mut service: AppServiceClient<Box<dyn ReadWrite>> = link.open().await?;

    let environment = env_dict(&options.env);
    let argv: Vec<&str> = options.arguments.iter().map(|s| s.as_str()).collect();

    let response = service
        .launch_application(
            options.bundle_id.clone(),
            &argv,
            options.kill_existing,
            false,
            Some(environment),
            None,
            None,
        )
        .await
        .map_err(|e| format!("launchapplication failed: {e}"))?;

    LOG.log(format!(
        "started {} as pid {} (CoreDevice)",
        options.bundle_id, response.pid
    ));

    Ok(format!(
        "MHL launched {} (pid {}) via CoreDevice with the Metal HUD injected.",
        options.bundle_id, response.pid
    ))
}

async fn launch_via_dvt(link: &mut DeviceLink, options: &LaunchOptions) -> Result<String, String> {
    let mut server: RemoteServerClient<Box<dyn ReadWrite>> = link.open().await?;

    let pid = {
        let mut control = ProcessControlClient::new(&mut server)
            .await
            .map_err(|e| format!("processcontrol channel failed: {e}"))?;

        control
            .launch_app(
                options.bundle_id.clone(),
                Some(env_dict(&options.env)),
                Some(args_dict(&options.arguments)),
                false,
                options.kill_existing,
            )
            .await
            .map_err(|e| format!("DVT launchSuspendedProcess failed: {e}"))?
    };

    LOG.log(format!(
        "started {} as pid {pid} (DVT)",
        options.bundle_id
    ));
    Ok(format!(
        "MHL launched {} (pid {pid}) via the instruments service with the Metal HUD injected.",
        options.bundle_id
    ))
}

/// Capture the device screen to `path` (PNG). Used to prove the HUD is visible.
///
/// CoreDevice's screencaptureservice and the older screenshotr shim are both
/// tried; whichever the device advertises wins.
pub async fn screenshot(pairing_path: &str, path: &str) -> Result<String, String> {
    let mut link = tunnel::connect(pairing_path).await?;

    let bytes = match screenshot_via_core_device(&mut link).await {
        Ok(bytes) => bytes,
        Err(core_error) => {
            LOG.log(format!("screencaptureservice failed: {core_error}"));
            screenshot_via_screenshotr(&mut link).await?
        }
    };

    tokio::fs::write(path, &bytes)
        .await
        .map_err(|e| format!("cannot write {path}: {e}"))?;

    LOG.log(format!("screenshot saved to {path} ({} bytes)", bytes.len()));
    Ok(format!("Saved {path} ({} bytes)", bytes.len()))
}

async fn screenshot_via_core_device(link: &mut DeviceLink) -> Result<Vec<u8>, String> {
    use idevice::services::core_device::{ImageFormat, ScreenCaptureServiceClient};

    let mut capture: ScreenCaptureServiceClient<Box<dyn ReadWrite>> = link.open().await?;
    capture
        .take_screenshot(None, ImageFormat::Png)
        .await
        .map_err(|e| format!("capturescreenshot failed: {e}"))
}

async fn screenshot_via_screenshotr(link: &mut DeviceLink) -> Result<Vec<u8>, String> {
    use idevice::services::screenshotr::ScreenshotService;

    let mut client: ScreenshotService = link.open().await?;
    client
        .take_screenshot()
        .await
        .map_err(|e| format!("screenshotr failed: {e}"))
}
