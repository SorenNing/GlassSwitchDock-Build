# Native regression harness contract

Owner scope: `tests/**` and optional `tools/test-local.py` only. Vendor, runtime, preferences and build scripts remain owned by the parent/build agent.

The harness must compile actual `src/NGSwitch.m`, `src/NGDock.mm`, `src/NGResources.m`, `src/NGPreferences.m`, guarded `src/Tweak.m`, all pinned vendor implementations, `src/TheseusBridge.swift` and `src/TheseusBundle.swift`. Build module name: `GlassSwitchDock`; define `NG_TESTING=1` for ObjC/C++ and Swift. `tests/Harness/main.m` launches UIApplication and performs tests after creating a visible UIWindow. It requires a simulator **.app**, not a command-line UIKit process, and writes `report.json` and PNG evidence to `NG_TEST_OUTPUT` (or app Documents/NGRegression).

Production runtime contract read by tests through `src/Bridge.h`:

```objc
void NGPreferencesReload(void);
void NGRefreshSwitch(UISwitch *source);
void NGRefreshDocks(void);
NSBundle *NGBundleResources(void);
NSBundle *NGBundleGlassify(void);
```

Test preference changes use production `NGStorePreference(key,value)` then `NGPreferencesReload()`. `NG_TEST_PREFS` isolates the production file path inside the app sandbox; runner also passes `NG_TEST_PREFS_DOMAIN=com.ning.glassswitchdock` for CFPreferences snapshot/restore. Tests restore both original CFPreferences values and original test-file contents at completion. Actual source `UISwitch` sends `UIControlEventValueChanged`; no fake overlay component implementation is linked.

Theseus Swift bridge expected ObjC runtime class `NGTheseusSwitch`, deriving UIView, wrapping the unchanged original `TheseusSwitch` at 63x28. Required `setOn:animated:` and state getter `isOn` or `on`; `onChanged` block receives BOOL. Do not add styling parameters. Harness discovers the sole Theseus sibling overlay through hierarchy class identity. Theseus runs original `accessibilityActivate()` and shipped `scriptedTouchBegan/Moved/Ended`. Glassify remains available only as a Dock material, with no compiled switch implementation. It never calls the wrapper callback block directly.

Resources must resolve in the harness from `NSBundle.mainBundle.resourceURL/GlassSwitchDockResources.bundle` (nested `GlassifyShaders.bundle`) in addition to production installation locations. Tests fail if Metal is unavailable or a metallib cannot load. No fallback-to-static-colors counts as a pass.

Dock tests call exported production `NGRefreshDock(UIView *)` and `NGRefreshDocks()` on synthetic classes `SBDockView` / `SBFloatingDockPlatterView` with a real `backgroundView` getter. After pumping the GPU first frame they refresh again (no constructor hooks run). Tests compare every Clear optical field including internal lens-chain/rim to the live vendor preset except the single requested Dock-only `glassRim.bandBias` change from -0.3 to 0, which is asserted separately; container radius/capsule/padding/insets and the capture backend are treated as geometry/backend adaptation. Both dynamic styles also test capture budgeting under repeated forced/layout calls, unchanged-frame draw suppression, source-discovery reuse, hidden-dock capture suspension, initial native fallback and retention of the last valid frame across transient failures. Glassify uses stock GLSGlassView Clear + secondarySystemFillColor, no labels/sliders or touch interception. Real GPU snapshots must change after the patterned background changes. Private SpringBoard is not loaded; evidence describes these as synthetic dock integration tests.

Exact original default configuration assertions are derived from the pinned vendor initializers, and originals are checked byte-for-byte by the portable test. No iOS 26 style override, private UISwitch slider mutation, font customization, or global UIAppearance changes are acceptable.

Build owner invocation to support: `make smoke` producing `build/simulator/GlassSwitchDockHarness.app` (or report actual path); run `tests/run-simulator.sh --app <path> --device <UDID-or-booted> --output <directory>`. The runner only uses local `xcrun simctl`; it neither dispatches remote builds nor installs to physical devices. Set app bundle ID `com.minis.GlassSwitchDockHarness`, main `tests/Harness/main.m`, add all `tests/Harness/*.m` / `*.mm`, **append `tests/Harness/NGTheseusProbe.swift` to the SAME Swift module compilation as the vendor and bridge**, and copy both resource metallibs into the app. The Swift probe reads real Theseus configuration (including internal lens/rim data) and calls its shipped scriptedTouch methods; it adds no implementation substitute. Runner passes prefs domain derived from the original Root.plist through environment.

No native Xcode/UIKit execution is available in the current Linux/iSH environment. Portable structural tests will be run locally; native status remains unexecuted until the macOS runner produces report.json and screenshots.
