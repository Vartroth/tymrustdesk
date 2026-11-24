# tymrustdesk macOS build

Custom RustDesk client for macOS (arm64 and x86_64) bound to the private
server `tymsoftware.com`. Requirements, decisions and history live in
`odd/tasks/tymrustdesk-macos.md`.

The branding and server settings are already committed on the
`feat/tymrustdesk-macos` branch (and in the `tymrustdesk` branch of the
`libs/hbb_common` fork), so a rebuild only needs the toolchain below.

## 1. Clone

```sh
git clone -b feat/tymrustdesk-macos git@github.com:Vartroth/tymrustdesk.git
cd tymrustdesk
git submodule update --init --recursive
```

## 2. Toolchain (arm64 Mac, Xcode installed)

Everything except Homebrew packages goes under `~/sdk` (`SDK_DIR`).

```sh
brew install rustup llvm gnu-sed create-dmg cocoapods pkgconf
rustup toolchain install 1.81 1.75
rustup target add x86_64-apple-darwin --toolchain 1.81
cargo +1.75 install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
cargo +1.75 install cargo-expand --version 1.0.95 --locked

mkdir -p ~/sdk && cd ~/sdk
# NASM 2.16.03: https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/macosx/
#   unzip nasm-2.16.03-macosx.zip  -> ~/sdk/nasm-2.16.03
# Flutter 3.44.9 (arm64 build) and 3.24.5 (x86_64 build), macOS arm64 zips:
#   https://docs.flutter.dev/release/archive -> ~/sdk/flutter-3.44.9, ~/sdk/flutter-3.24.5
#   Patch 3.24.5 like CI does: inside ~/sdk/flutter-3.24.5 run
#   git apply <repo>/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff

# vcpkg at the commit pinned in .github/workflows/flutter-build.yml (VCPKG_COMMIT_ID)
git clone https://github.com/microsoft/vcpkg && cd vcpkg
git checkout 9e593bb18ea69cc5095e012465dcd675a822ed0d && ./bootstrap-vcpkg.sh
export VCPKG_ROOT=~/sdk/vcpkg
cd <repo>
$VCPKG_ROOT/vcpkg install --triplet arm64-osx --x-install-root="$VCPKG_ROOT/installed"
# x64 needs its own install root, because a manifest install removes the other triplet:
$VCPKG_ROOT/vcpkg install --triplet x64-osx --host-triplet x64-osx \
  --x-install-root="$VCPKG_ROOT/installed-x64"
ln -s "$VCPKG_ROOT/installed-x64/x64-osx" "$VCPKG_ROOT/installed/x64-osx"
```

## 3. Build

```sh
res/tymrustdesk/build-macos.sh arm64    # -> dist/tymrustdesk-<version>-aarch64.dmg
res/tymrustdesk/build-macos.sh x86_64   # -> dist/tymrustdesk-<version>-x86_64.dmg
```

Without extra variables the app is signed ad-hoc (only for local testing).

## 4. Sign and notarize

Needs the `Developer ID Application: MyD Bajo Aragon SL (8K4TBXTC7H)`
identity in the login keychain (restore it from the `.p12` backup) and a
notarytool profile:

```sh
xcrun notarytool store-credentials tymrustdesk \
  --apple-id info.agonzalez@gmail.com --team-id 8K4TBXTC7H

export SIGN_IDENTITY="Developer ID Application: MyD Bajo Aragon SL (8K4TBXTC7H)"
export NOTARY_PROFILE=tymrustdesk
res/tymrustdesk/build-macos.sh arm64
res/tymrustdesk/build-macos.sh x86_64
```

A dmg that is already signed can be notarized later without rebuilding:

```sh
xcrun notarytool submit dist/<file>.dmg --keychain-profile tymrustdesk --wait
xcrun stapler staple dist/<file>.dmg
```

## Notes

- Both architectures share `flutter/build/...`; the last build overwrites it.
  Install from the dmg and always launch `/Applications/tymrustdesk.app`.
- After installing, grant Screen Recording and Accessibility, then restart the
  app; otherwise peers stay on "waiting for image".
- Running `cargo test` on this machine writes into the real app config
  (`~/Library/Preferences/com.carriez.tymrustdesk`), because the app name is
  `tymrustdesk`.
