# GlassSwitchDock

One jailbreak tweak, one package identifier `com.ning.glassswitchdock`, and one PreferenceLoader entry. The package contains both switch replacement and desktop Dock background material. No separate engine package is required.

Exactly three settings:

1. 启用开关 — original Theseus, enabled by default.
2. 启用 Dock 玻璃 — enabled by default.
3. Dock 玻璃样式 — Theseus Clear (default) or Glassify Prominent Clear.

Only the original Theseus switch is used. Its dimensions, materials, colours and animation/physics defaults are unmodified. A sibling overlay keeps its original 63×28 track while forwarding one logical change to the native UISwitch; programmatic updates, disabled state, reparenting and restoration are handled by the integration code. The Glassify switch replacement and selection preference are removed; its archived original source is not compiled into the product.

The Dock integration replaces only its background. Icons, placement, launches and dragging remain system-owned. Version 0.1.3 restores dynamic Theseus Clear and keeps dynamic Glassify Prominent Clear. The static image, offline baker, conversion tool and static-resource package requirement are removed. The only optical adjustment is `glassRim.bandBias = 0` on the Theseus Dock instance, replacing its negative lateral-band bias; the original switch, Glassify material, face colour and refraction parameters remain unchanged. This is a candidate reduction of the reported dark contour, not a hardware-verified fix.

Both Dock styles share coalesced layout refresh, a cached wallpaper source and reusable image renderer. Capture attempts cannot exceed one per 0.25 seconds even when layout callers request forced capture. Equal image bytes do not publish a new generation or request a new GPU draw. After consecutive unchanged captures, polling backs off to 0.5 then 1 second; newly detected content restores 0.25 seconds. This saves work on still wallpaper, with up to roughly one second of detection latency after idle. Offscreen or hidden Dock ancestors suspend capture and the owned renderer. Invalid first input retains native glass; a later failed capture retains the last good live input to avoid background flicker. UIKit capture remains on the main thread, at the original resolution and 96-point margin.

Production Theseus uses GPU-present readiness without per-frame CPU snapshot readback. Glassify retains an output texture only until the first queued render and asynchronous GPU fence complete, then stops the redundant per-frame output copy. Simulator assertions keep readback enabled for pixel evidence. No global quality changes, new settings or new switch styles are introduced. All 89 original vendor files remain byte-identical. Native Swift compilation, simulator regression, hardware appearance and measured frame-time improvement are pending; portable checks alone do not prove smoothness.

Pinned originals:

- [Theseus](https://github.com/valzevul/Theseus): `71ca1c127a4e7fe3387361f160c4890dbd427f66`.
- [Glassify](https://github.com/dotdot911/Glassify): `a8e52aa9c015502fb68d5f81687698f11df6977d`.

All 89 original distribution files are checked against `Vendor/manifest.json`. Source comments, licences and NOTICE files are preserved. Integration by Ning; upstream authors Vadim Drobinin and Hung Phan.

## Build and verification

Use the manual **Native GlassSwitchDock** GitHub Actions workflow. macOS/Xcode compiles the actual Swift, Objective-C++, C++ and Metal code and runs the UIKit simulator harness. The workflow builds and delivers only real arm64e RootHide, with one deb.

Portable checks: `make check`, `make infra-check`, `python3 tools/test-local.py`.
Native checks: `make smoke`, `bash tools/run-ci-simulator.sh`, `make build ARCH=arm64e`, `make verify`.

Final debs are re-extracted and checked for exact installation layout, entry/resource uniqueness, original Metal output, actual CPU subtype, dependency binding, hashes and strict native signatures. The installer does not respring or terminate processes.

Simulator tests exercise original controls, real GPU pipelines and synthetic Dock views. They are not physical-device SpringBoard or real HID/XCUITest validation. Device appearance, wallpaper capture, third-party tweak compatibility and performance still require on-device testing. Never treat a successful compile as proof of those outcomes.
