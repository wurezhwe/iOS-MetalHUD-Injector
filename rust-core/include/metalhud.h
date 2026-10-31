// MetalHUD FFI - C interface used by the SwiftUI app.
//
// Every call is blocking. Run them off the main thread (Task.detached is fine).
// Progress during a blocking call comes through the log callback installed with
// mh_log_init(); the callback may fire from any thread.
#ifndef METALHUD_H
#define METALHUD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Receives every log line. `msg` is only valid for the duration of the call.
typedef void (*mh_log_cb)(void *ctx, const char *msg);

/// Installs the log callback. Returns 0 on the first call, 1 afterwards.
int32_t mh_log_init(mh_log_cb cb, void *ctx);

/// Frees a string returned by this library.
void mh_string_free(char *s);

/// Library version, caller frees with mh_string_free().
char *mh_version(void);

/// Candidate gateway addresses for the RSD dial (e.g. "10.7.0.1").
/// Pass NULL/0 to fall back to the built-in defaults.
int32_t mh_set_hosts(const char **hosts, size_t count);

/// Forgets the cached tunnel route; call after switching VPNs.
void mh_clear_route(void);

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------

/// Fires once the listener is bound. Publish `service_id` over Bonjour with
/// type "_remotepairing-pairable-host._tcp." on `port`, using the TXT records
/// in (txt_keys[i], txt_vals[i]). All pointers are valid only during the call.
typedef void (*mh_pair_ready_cb)(void *ctx,
                                 const char *service_id,
                                 uint16_t port,
                                 const char *const *txt_keys,
                                 const char *const *txt_vals,
                                 size_t txt_count);

/// Fires with the PIN the user must confirm in Settings.
typedef void (*mh_pair_pin_cb)(const char *pin, void *ctx);

/// Result of one pairing run. Free with mh_pairing_result_free().
typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
    char *host_alt_irk_hex;
} MhPairResult;

/// Runs the RemotePairing host. BLOCKS until paired or failed.
/// `port` 0 lets the OS choose. `host_alt_irk_hex` may be NULL or "" the first
/// time; pass the value from the previous run to keep the identity stable.
/// Returns 0 on success (out->pairing_file_path is set), non-zero on failure.
int32_t mh_pairing_run_host(const char *bind_addr,
                            uint16_t port,
                            const char *name,
                            const char *model,
                            const char *out_path,
                            const char *host_alt_irk_hex,
                            mh_pair_ready_cb ready_cb,
                            mh_pair_pin_cb pin_cb,
                            void *ctx,
                            MhPairResult *out);

void mh_pairing_result_free(MhPairResult *r);

// ---------------------------------------------------------------------------
// Device queries
// ---------------------------------------------------------------------------

/// Lists installed apps. On success *out receives a JSON array of
/// {"bundleId","name","version","developer"}. Frees with mh_string_free().
/// Returns 0 on success.
int32_t mh_list_apps(const char *pairing_path, char **out, char **err);

/// Opens a tunnel and reports what the device advertises.
/// *out receives {"host","services","appService","dvt"}.
int32_t mh_probe_device(const char *pairing_path, char **out, char **err);

/// Launches `bundle_id` with extra environment variables.
/// `env_json` is a JSON object such as {"MTL_HUD_ENABLED":"1"} (NULL for none).
/// `args_json` is a JSON array of arguments (NULL for none).
int32_t mh_launch_app(const char *pairing_path,
                      const char *bundle_id,
                      const char *env_json,
                      const char *args_json,
                      bool kill_existing,
                      char **out,
                      char **err);

/// Writes a PNG screenshot of the device screen to `out_path`.
int32_t mh_screenshot(const char *pairing_path,
                      const char *out_path,
                      char **out,
                      char **err);

#ifdef __cplusplus
}
#endif

#endif /* METALHUD_H */
