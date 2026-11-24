#!/usr/bin/env bash
# Build the tymrustdesk macOS .dmg for one architecture on an arm64 Mac.
#
# Usage: res/tymrustdesk/build-macos.sh arm64|x86_64
#
# Requires the toolchain described in odd/tasks/tymrustdesk-macos.md:
#   SDK_DIR (default ~/sdk) with nasm-2.16.03, flutter-3.44.9, flutter-3.24.5
#   and vcpkg (VCPKG_ROOT) holding arm64-osx and x64-osx under installed/.
# Temporary source edits (Flutter 3.44 patch, deployment targets, pubspec)
# are reverted on exit; the script refuses to run if those files are dirty.
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY (e.g. "Developer ID
# Application: ...") to sign with hardened runtime, and NOTARY_PROFILE (a
# `xcrun notarytool store-credentials` profile) to also notarize and staple.
set -euo pipefail

arch=${1:-}
case "$arch" in
arm64 | x86_64) ;;
*)
  echo "usage: $0 arm64|x86_64" >&2
  exit 2
  ;;
esac

repo=$(git rev-parse --show-toplevel)
cd "$repo"

sdk=${SDK_DIR:-$HOME/sdk}
export VCPKG_ROOT=${VCPKG_ROOT:-$sdk/vcpkg}
export PATH="$sdk/nasm-2.16.03:/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:/opt/homebrew/opt/llvm/bin:$PATH"
export LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib
export CPATH="$(xcrun --show-sdk-path)/usr/include"

temp_files=(Cargo.toml build.py flutter/lib/common.dart flutter/lib/common/widgets/dialog.dart
  flutter/macos/Podfile
  flutter/macos/Podfile.lock flutter/macos/Runner.xcodeproj
  flutter/pubspec.yaml flutter/pubspec.lock)
if [[ -n "$(git status --porcelain -- "${temp_files[@]}")" ]]; then
  echo "Uncommitted changes in files this script edits temporarily:" >&2
  git status --short -- "${temp_files[@]}" >&2
  exit 1
fi
trap 'git checkout -q -- "${temp_files[@]}"' EXIT

version=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
app=flutter/build/macos/Build/Products/Release/tymrustdesk.app

codegen() {
  RUSTUP_TOOLCHAIN=1.75 flutter_rust_bridge_codegen \
    --rust-input ./src/flutter_ffi.rs \
    --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h
}

set_min_macos() {
  /usr/bin/sed -i '' -e "s/platform :osx, '.*'/platform :osx, '$1'/" flutter/macos/Podfile
  /usr/bin/sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9]*.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = $1;/" \
    flutter/macos/Runner.xcodeproj/project.pbxproj
  export MACOSX_DEPLOYMENT_TARGET=$1
}

if [[ "$arch" == arm64 ]]; then
  export PATH="$sdk/flutter-3.44.9/bin:/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
  bash .github/patches/apply_flutter_3.44_source_patches.sh
  (cd flutter && flutter pub get)
  codegen
  set_min_macos 12.3
  /usr/bin/sed -i '' -e "s/MACOSX_DEPLOYMENT_TARGET\=[0-9]*.[0-9]*/MACOSX_DEPLOYMENT_TARGET=12.3/" build.py
  /usr/bin/sed -i '' -e "s/osx_minimum_system_version = \"[0-9]*.[0-9]*\"/osx_minimum_system_version = \"12.3\"/" Cargo.toml
  rm -f target/release/liblibrustdesk.dylib target/release/librustdesk.dylib target/release/service
  RUSTUP_TOOLCHAIN=1.81 python3 build.py --flutter --hwcodec --unix-file-copy-paste --screencapturekit
  dmg_arch=aarch64
else
  export PATH="$sdk/flutter-3.24.5/bin:$PATH"
  /usr/bin/sed -i '' 's/extended_text: 14.0.0/extended_text: 13.0.0/' flutter/pubspec.yaml
  (cd flutter && flutter pub get)
  codegen
  git checkout -q -- flutter/pubspec.yaml flutter/pubspec.lock
  (cd flutter && flutter pub get)
  set_min_macos 12.0
  RUSTUP_TOOLCHAIN=1.81 cargo build --locked --release --target x86_64-apple-darwin \
    --features flutter,hwcodec,unix-file-copy-paste
  out=target/x86_64-apple-darwin/release
  cp "$out/liblibrustdesk.dylib" target/release/liblibrustdesk.dylib
  cp "$out/liblibrustdesk.dylib" target/release/librustdesk.dylib
  cp "$out/service" target/release/service
  (cd flutter && FLUTTER_XCODE_ARCHS=x86_64 FLUTTER_XCODE_ONLY_ACTIVE_ARCH=NO flutter build macos --release)
  cp target/release/service "$app/Contents/MacOS/"
  dmg_arch=x86_64
fi

for bin in "$app/Contents/MacOS/tymrustdesk" "$app/Contents/MacOS/service" \
  "$app/Contents/Frameworks/liblibrustdesk.dylib"; do
  [[ "$(lipo -archs "$bin")" == "$arch" ]] || { echo "$bin is not $arch" >&2; exit 1; }
done

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  bash .github/scripts/sign-macos-app.sh "$app" "$SIGN_IDENTITY" \
    flutter/macos/Runner/Release.entitlements
else
# Ad-hoc signature without hardened runtime: with --options runtime, dyld
# rejects the ad-hoc signed FlutterMacOS.framework ("different Team IDs").
sign() { codesign --force --sign - "$@"; }
while IFS= read -r -d '' code; do
  if file -b "$code" | grep -q 'Mach-O'; then sign "$code"; fi
done < <(find "$app/Contents/Frameworks" -type f -print0)
while IFS= read -r -d '' framework; do
  sign "$framework"
done < <(find "$app/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
sign "$app/Contents/MacOS/service"
sign --entitlements flutter/macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict "$app"
fi

mkdir -p dist
dmg="dist/tymrustdesk-$version-$dmg_arch.dmg"
rm -f "$dmg"
create-dmg --volname "tymrustdesk Installer" --icon "tymrustdesk.app" 200 190 \
  --hide-extension "tymrustdesk.app" --window-size 800 400 \
  --app-drop-link 600 185 "$dmg" "$app"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature -v "$dmg"
  fi
fi
echo "Built $dmg"
