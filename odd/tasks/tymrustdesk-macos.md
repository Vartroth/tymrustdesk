Objective: local macOS build of a RustDesk custom client "tymrustdesk" (arm64 + x86_64) bound to the private server tymsoftware.com.
Branch: feat/tymrustdesk-macos on base c50ae9751 (submodule libs/hbb_common on local branch tymrustdesk, base fae47e0). Delivery: ask-on-risk. Runner: cargo test --lib (Rust), flutter analyze, local build via res/tymrustdesk/build-macos.sh.

## Specs

- S1: App name "tymrustdesk" ("quiero construir una custom client para mac os de rustdesk que debe llamarse tymrustdesk").
- S2: Embedded server: "tymsoftware.com es el server y el relay y la clave 8OjJVOHUd62wZuL7NxFtlWAgFBBvWyD1pYyti7ILJps=".
- S3: Targets: "la app no la quiero para iphone, la quiero para macos arm y x86".
- S4: Build route: "Compilar localmente" (user choice; no CI fork).
- S5: Branding: "ademas quiero poner mi logo" / "tengo una imagen logo.png puedes generar las imagenes que necesites a partir de esa".
- S6: "hay que dejar la info de conmexion y politica de privacidad y todo lo configurable de rustdesk con los datos de tymsoftware.com". Decisions: privacy https://tymsoftware.com/politica-de-privacidad; web/downloads https://tymsoftware.com; copyright "TYM Software"; server OSS (hbbs/hbbr, no API); network settings "Visibles y bloqueados"; updates "Desactivarla".
- S7: Signing: "soy desarrollador de apple, quiero firmarlo". Identity "Developer ID Application: MyD Bajo Aragon SL (8K4TBXTC7H)", notarytool keychain profile "tymrustdesk".
- Assumption: bundle id com.tymsoftware.tymrustdesk (not specified by user).

## Tasks

- T1 [S1,S2] inline — RENDEZVOUS_SERVERS/RS_PUB_KEY/APP_NAME in libs/hbb_common/src/config.rs; PRODUCT_NAME/bundle id in AppInfo.xcconfig — done
- T2 [S1] inline — rename-breaking hardcodes: pbxproj target-level PRODUCT_BUNDLE_IDENTIFIER (3x), build.py service copy path — done
- T3 [S4] inline — toolchain in ~/sdk (tym-env.sh): rust 1.81/1.75, Flutter 3.44.9 (zip) + 3.24.5 (patched), vcpkg arm64-osx + x64-osx, NASM 2.16.03, frb codegen 1.80.1 — done
- T4 [S4] inline — bridge codegen per arch (inside build script) — done
- T5 [S3] inline — arm64 .dmg (min macOS 12.3) — see T10
- T6 [S3] inline — x86_64 .dmg cross-built on arm64 (min macOS 12.0) — see T10
- T7 [S1,S2] inline — smoke check: launch, bundle id, log shows tymsoftware.com:21116 — done (redone after incident)
- T8 [S5] inline — branding: vector redraw res/tymrustdesk/*.svg → AppIcon.icns, res/mac-icon.png, flutter/assets/icon.png, res/mac-tray-dark-x2.png — done
- T9 [S6] inline — load_tymrustdesk_settings() in src/common.rs hooked in load_custom_client; server dialog read-only when fixed; privacy/web/download/copyright — done (RED→GREEN observed pre-incident)
- T11 [S7] inline — SIGN_IDENTITY / NOTARY_PROFILE in build-macos.sh (reuses .github/scripts/sign-macos-app.sh); both dmgs notarized, stapled, spctl "Notarized Developer ID" — done
- T10 [S3,S6] inline — res/tymrustdesk/build-macos.sh + rebuild both dmgs — done in the fork clone: dist/tymrustdesk-1.5.3-{aarch64,x86_64}.dmg verified (privacy URL, no rustdesk.com/privacy, TYM Software, bundle id, arch, signature, --version 1.5.3), live x86_64 connect to tymsoftware.com:21116

## Log

- L1 (2026-11-19): "quiero construir una custom client para mac os de rustdesk que debe llamarse tymrustdesk con datos de conexion de mi server privado"
- L2 (2026-11-19): "tymsoftware.com es el server y el relay y la clave 8OjJVOHUd62wZuL7NxFtlWAgFBBvWyD1pYyti7ILJps= la app no la quiero para iphone, la quiero para macos arm y x86"
- L3: hbb_common has no option_env! for server/key (config.rs consts) → patched submodule on a local branch. Relay derived from the rendezvous host (port 21117).
- L4: User chose local build. Host arm64, macOS 27, Xcode 27.2.
- L5 (2026-11-19): "ademas quiero poner mi logo"; "tengo una imagen logo.png puedes generar las imagenes que necesites a partir de esa". logo.png was 48x48 → redrawn as SVG (#6B8E23, chip, -10° tilt). loadIcon (flutter/lib/common.dart) prefers assets/icon.png over icon.svg → additive. *png/*svg are gitignored → force-added.
- L6 (2026-11-20): "se me ha colgado" — curl/dart stalled for hours after a network drop; resumed with curl --speed-limit/--speed-time retries; network steps wrapped in timeout.
- L7: Xcode 27 rejects deployment targets < 12.0 → Podfile post_install raises pods to 12.0. Ad-hoc signing with hardened runtime makes dyld reject FlutterMacOS.framework ("different Team IDs") → sign ad-hoc without --options runtime.
- L8: vcpkg.json ffmpeg is "host": true → x64-osx needs --host-triplet x64-osx; that manifest install removes arm64-osx packages, so x64 lives in ~/sdk/vcpkg/installed-x64/x64-osx, symlinked into installed/.
- L9: Flutter 3.24.5 builds x86_64 fine on Xcode 27 (FLUTTER_XCODE_ARCHS=x86_64, ONLY_ACTIVE_ARCH=NO).
- L10 (2026-11-20): user answers swapped URLs (privacy=/privacy is 404, web=/politica-de-privacidad); verified with curl, user confirmed the correction. Left untouched: "Powered by RustDesk" attribution and AGPL license text, rustdesk.com/pricing (only shown on the public server), mobile pages (not built). With an empty api-server the client tries http://tymsoftware.com:21114/api/sysinfo and falls back to TCP 21116 (warning only on OSS).
- L11 (2026-11-20): "cuando ejecuto me dice que falta 1 permiso de recording audio y ya esta" — microphone permission is optional (only for sending audio); ad-hoc signed rebuilds make macOS forget TCC grants.
- L14 (2026-11-20): fork master ships a newer apply_flutter_3.44_source_patches.sh that also edits flutter/lib/common/widgets/dialog.dart (selectAllOnFocus, 3.44-only); the script did not revert it, so the following x86_64 build (Flutter 3.24.5) failed. Added the file to temp_files; rebuild OK. Rust lib suite 260/260 passed on the reconstructed branch before the rebase.
- L13 (2026-11-20): user forked to /Users/adrian/projects/app/tymrustdesk (origin git@github.com:Vartroth/tymrustdesk.git). Branch rebased cleanly onto fork master 144a743d0 (7 upstream commits ahead). User chose "Fork de hbb_common": .gitmodules → https://github.com/Vartroth/hbb_common; submodule commit bb9d282 pushed to Vartroth/hbb_common branch tymrustdesk; feat/tymrustdesk-macos pushed to origin (user-authorized). Fresh clone + submodule init verified.
- L12 (2026-11-20): "lo ha borrado un limpiador" — the whole repo (unpushed commits, local submodule commit, dist/, user's logo.png) was deleted by a cleaner app; no Time Machine or local snapshots. ~/sdk toolchain and the SVG sources in the session temp dir survived. Re-cloned upstream at the same base and reapplied every change verbatim.
- L15 (2026-11-23): "soy desarrollador de apple, quiero firmarlo". Xcode refused Developer ID ("only the Account Holder") although App Store Connect shows Account Holder for team MyD Bajo Aragon SL; Xcode showed only Admin. Cert created on developer.apple.com with a Keychain-generated CSR. With a real identity, hardened runtime works (the ad-hoc "different Team IDs" issue does not apply).
- L16 (2026-11-24): the notarytool keychain profile vanished between the arm64 and x86_64 runs (cause unknown, possibly the cleaner app); user re-stored it and the already-signed x86_64 dmg was notarized without rebuilding. Both dmgs: status Accepted, stapled, spctl source=Notarized Developer ID.
- L17 (2026-11-24): "quiero que subas a mi repo las modificaciones de este repo y dejarlo para por si nevesitamos esto otra vez, asi mismo necesito que me limpies lo que hemos instalado para poder compilarlo". Added res/tymrustdesk/README.md (toolchain setup, build, signing). Discarded 34 unrelated flutter/lib edits (automatic MaterialState→WidgetState migration, not ours). Removed the build toolchain: ~/sdk, ~/.rustup, ~/.cargo, target/, flutter/build, brew rustup/llvm/gnu-sed/create-dmg. Kept dist/*.dmg, Developer ID identity, notarytool profile, CocoaPods, pkgconf, ~/.pub-cache (pre-existing). Installed app at /Applications works after granting Screen Recording/Accessibility.
