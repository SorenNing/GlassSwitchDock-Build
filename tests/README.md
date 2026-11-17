# Regression tests

Run from the repository root. Portable checks are available on Linux and macOS:

```sh
python3 tools/test-local.py
bash -n tests/run-simulator.sh
```

`tests/evidence/local-report.json` records executed checks, source digests and explicitly `nativeUIKit.executed=false`. The portable suite verifies every original vendor byte against the pinned manifest, separately pins Theseus `71ca1c127a4e7fe3387361f160c4890dbd427f66` and Glassify `a8e52aa9c015502fb68d5f81687698f11df6977d`, enforces 33 original Swift + 1 Metal / 4 C++ + 16 archived original ObjC++ implementations (15 compiled; GLSSwitch.mm excluded), the one-domain three-setting schema, original switch defaults, absence of demo UI/global typography/style overrides and test/runtime interfaces. Four negative tests prove the native-report validator rejects an empty success, failed assertions, duplicate checks, missing screenshots and unchanged GPU evidence. Metadata UPSTREAM.json files are separately revision-pinned; they are not represented as upstream release bytes.

On a local Mac with full Xcode and an available iOS Simulator:

```sh
make smoke
xcrun simctl list devices available
bash tests/run-simulator.sh \
  --app build/simulator/GlassSwitchDockHarness.app \
  --device '<SIMULATOR_UDID>' \
  --output evidence/native-regression
```

Use `--device booted` only when exactly one Simulator is booted. The runner boots the specified Simulator if needed, installs only the uniquely identified harness app, launches it and collects report/PNG/log files. It makes no remote build calls, network calls or physical-device installs. Xcode's `make smoke` compiles the actual runtime, untouched vendor implementations and tests in one app. `NGTheseusProbe.swift` must be included in the same `GlassSwitchDock` Swift module, and `NG_TESTING=1` disables only automatic tweak hook installation. Production exported refresh/sync/store/resource functions are called directly.

Native assertions cover:

- Original TheseusSwitch child inside the UIView NGTheseusSwitch bridge; 63×28 defaults, no transform/default color/material/layout changes.
- Windowed native UISwitch state and six programmatic sync transitions without callbacks; true Theseus accessibility activation plus shipped scripted drag; exactly one native valueChanged per user change and unrelated controls unchanged.
- Enabled/disabled states, repeated refresh, disable/re-enable transitions, retained state, sibling detachment/reparenting, and restoration of native alpha/interaction/accessibility including nondefault host values.
- Real root and nested metallib loading, shader lookup and render/compute pipeline construction. The original `gls_downsample13` kernel executes on the Simulator Metal device and its output is read back against known RGBA values. Unavailable Metal/resources or static fallback fails the suite.
- Both synthetic SBDockView and SBFloatingDockPlatterView backgrounds: Theseus Clear's optical preset with only the explicitly requested Dock side-band bias neutralized and its live Metal backend, Glassify's exact Clear + secondarySystemFillColor configuration, no labels/sliders/control children, no intercepting icon hit tests, one material per dock and background restoration. Pattern changes must change the original GPU output checksums. Eight GPU PNGs and six UIKit screenshots are produced in addition to simulator-screen.png.

`report.json` records assertion evidence, class identities, event counts and values, original/current optical fingerprints, shader names, actual texture readbacks and screenshot filenames. CI should treat the runner's exit code as mandatory; it internally executes:

```sh
python3 tests/validate-report.py evidence/native-regression/report.json
```

The validator fails if any mandatory scenario, screenshot or changed GPU frame is missing, even when a report claims `status=passed`. No skipped or unavailable native scenario is converted to a pass.

These are local Simulator integration tests, not hardware proof, not a real SpringBoard session and not HID/XCUITest touch delivery. UIKit snapshot PNGs require visual review; the separate GPU frame/readback assertions establish active shaders. Native compile/runtime execution was unavailable on the Linux/iSH authoring host and is intentionally recorded as not run until this Mac command produces evidence.
