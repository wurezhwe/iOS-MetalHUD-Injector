#!/usr/bin/env bash
# Build the Rust static library for iOS and package it as an xcframework.
#
# Run on macOS, or let .github/workflows/build.yml do it on a GitHub runner.
set -euo pipefail

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rust-core"

echo "==> rustup targets"
rustup target add aarch64-apple-ios 2>/dev/null || true

echo "==> cargo build (release, aarch64-apple-ios)"
cargo build --release --target aarch64-apple-ios

LIB="target/aarch64-apple-ios/release/libmetalhud_ffi.a"
if [[ ! -f "$LIB" ]]; then
  echo "error: $LIB was not produced" >&2
  exit 1
fi

echo "==> building MetalHUDFFI.xcframework"
cd "$ROOT"
rm -rf MetalHUDFFI.xcframework
mkdir -p MetalHUDFFI.xcframework/ios-arm64/Headers
cp "$ROOT/rust-core/$LIB" MetalHUDFFI.xcframework/ios-arm64/libmetalhud_ffi.a
cp rust-core/include/metalhud.h MetalHUDFFI.xcframework/ios-arm64/Headers/
cp rust-core/include/module.modulemap MetalHUDFFI.xcframework/ios-arm64/Headers/

cat > MetalHUDFFI.xcframework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key>
			<string>libmetalhud_ffi.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>libmetalhud_ffi.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

echo "==> done: $ROOT/MetalHUDFFI.xcframework"
