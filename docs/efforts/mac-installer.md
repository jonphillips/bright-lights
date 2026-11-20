# Effort — Install Bright Lights on the Mac

**Status:** Ready · **Summary:** `scripts/install-bright-lights` builds the Mac app, verifies it, installs it into
`/Applications` with a rollback, and reopens it. Every build carries its git commit, and Settings shows it. On
launch, the checking Mac re-registers the installed copy as its login item. No schema change.

**Implements:** [ADR-0003](../decisions/0003-the-mac-checks-the-sources.md), which says the mini's setup includes an
install step. **Model:** vinyl-fever `scripts/install-vinyl-fever` and its build stamp
(`VinylFeverCore/.../ConnectorBuildStamp.swift`, the `Write connector build stamp` phase in its `project.yml`).

## Why

The checker runs as a login item (`SMAppService.mainApp`), registered from whichever copy of the app turned
**Check sources on this Mac** on. Today that's the copy Xcode built, in its build folder. If that copy is cleaned or
replaced, the login item can quietly stop launching the app, and the nightly checks stop with no error. During the
S4/S5 device pass, nobody could also tell which commit a device was running.

## The work

1. **The build stamp, on every platform.** A build phase writes `BLBuild` (the short commit), `BLDirty` (`true` or
   `false`) and `BLBuiltAt` into the built app's `Info.plist`, as Vinyl Fever's phase does. A small `BuildStamp` value
   reads them, with `unknown` when they're missing. Settings gets an **About** row showing it, for example
   "53e94bd · clean · 2026-11-20 09:28". This applies to the iOS builds too, so a device pass can confirm the build.
2. **The login item follows the installed copy.** On macOS launch, if this Mac holds the checker lease and checking is
   on (`checkerEnabled`), and `SMAppService.mainApp.status` isn't `.enabled`, call `register()`. If that fails, log
   it under `SourceChecks` and show it in Settings' checker section, as `enableChecker` already does.
3. **`scripts/install-bright-lights`**, a trimmed copy of `install-vinyl-fever`. Keep its structure and messages, and:
   - **Options:** `--configuration Debug|Release` (default `Debug`), `-n` for a dry run that prints the plan and exits
     0, and `-h`.
   - **Build:** `xcodegen generate`, then `xcodebuild` for `platform=macOS` into `.build/InstallDerivedData`, through
     `quiet-run`.
   - **Verify before staging:**
     - `BLBuild` matches `git rev-parse --short HEAD` and isn't `unknown`. Warn, without failing, when `BLDirty` is
       `true`.
     - `codesign --verify --deep --strict`.
     - The signed entitlements include `com.apple.developer.aps-environment` = `development` and the
       `iCloud.com.jonphillips.BrightLights` container. Fail if the build would use the CloudKit Production
       environment, which waits for M2.
     - The embedded provisioning profile lists this Mac's Provisioning UDID. Don't pin a profile name, since signing
       is automatic.
   - **Quit the running app.** Count every process with the bundle ID `com.jonphillips.BrightLights`, including one
     with no window: the checker keeps running when its window is closed, so don't copy Vinyl Fever's
     `background only is false` filter. Ask before quitting, as Vinyl Fever does.
   - **Swap into `/Applications/BrightLights.app`**, keeping the previous copy until the steps after the swap pass,
     and restoring it if they fail.
   - **Reopen** the installed app if the script quit it. If the app wasn't running, print that **Check sources on this
     Mac** needs the app open once.
   - Drop everything about the MCP helper, the tunnel and the smoke test, since Bright Lights has none.
   - **Finish** with Vinyl Fever's two-column summary: build and signature, entitlements, provisioning, installed
     path, and reopened.
4. **`check-drift.sh` runs `scripts/install-bright-lights -n`**, so a broken script fails fast. Nothing in
   `check-drift` installs.
5. **`README.md`** gets an "Install on the Mac" section: run the script from a clean `main`, then turn on **Check
   sources on this Mac** once on the checking Mac.

## Tests (package)

`BuildStamp` reads a complete stamp, and reads `unknown` from a missing or partial one.

## Not in this effort

- Moving the script into jon-platform. That's recorded in jon-platform's `SEAM-LEDGER.md` and lifted when a third
  app needs one.
- Release signing, notarization and TestFlight (M2).

## Done when

`scripts/check-drift.sh` passes; closeout (ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

On the Mac that checks (the laptop until the mini takes over), run `scripts/install-bright-lights` from a clean `main`.
The summary passes, and Settings shows the same commit. Log out and back in. Bright Lights starts from
`/Applications` (System Settings → Login Items lists it), and the next night's checks run.
