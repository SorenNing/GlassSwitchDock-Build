# GlassSwitchDock

One jailbreak tweak, one package identifier `com.ning.glassswitchdock`, and one PreferenceLoader entry. The package contains both switch replacement and desktop Dock background material. No separate engine package is required.

Exactly three settings:

1. 启用开关 — original Theseus, enabled by default.
2. 启用 Dock 玻璃 — enabled by default.
3. Dock 玻璃样式 — Theseus Clear (default) or Glassify Prominent Clear.

Only the original Theseus switch is used. Its dimensions, materials, colours and animation/physics defaults are unmodified. A sibling overlay keeps its original 63×28 track while forwarding one logical change to the native UISwitch; programmatic updates, disabled state, reparenting and restoration are handled by the integration code. The Glassify switch replacement and selection preference are removed; its archived original source is not compiled into the product.

The Dock integration replaces only its background. Icons, placement, launches and dragging remain system-owned. Version 0.1.4 moves the existing Theseus Clear / Glassify Prominent Clear materials to a self-built render-server path. `NGDockBackground` keeps our established Dock locator. `NGSystemBackdrop` uses `CABackdropLayer` and our own named filters; `GlassSwitchDockRender.dylib` is compiled from our source and encodes the existing material shaders with the system input/output textures. No reference-plugin backend, matcher, shader or install-identity bypass is included.

The Dock screenshot driver and its polling timer are removed. The original Theseus switch and all 89 vendor inputs remain unchanged. The existing Dock-only Theseus `bandBias = 0` setting remains. Parameter publications are small tokened dictionaries, with GPU completion receipts; failure restores the native background. An exclusive frame lease prevents simultaneous GPU frames from overwriting intermediate textures.

See [SYSTEM-BACKDROP.md](SYSTEM-BACKDROP.md) for source ownership, process routing and limitations. This is a native-build candidate until the Apple Swift/Metal compilation and tests run. Actual SpringBoard/backboardd ABI, texture extents, visual quality and performance still require device validation. Local syntax and portable checks alone do not prove those outcomes.

Pinned originals:

- [Theseus](https://github.com/valzevul/Theseus): `71ca1c127a4e7fe3387361f160c4890dbd427f66`.
- [Glassify](https://github.com/dotdot911/Glassify): `a8e52aa9c015502fb68d5f81687698f11df6977d`.

All 89 original distribution files are checked against `Vendor/manifest.json`. Source comments, licences and NOTICE files are preserved. Integration by Ning; upstream authors Vadim Drobinin and Hung Phan.

## Build and verification

Use the manual **Native GlassSwitchDock** GitHub Actions workflow. macOS/Xcode compiles the actual Swift, Objective-C++, C++ and Metal code and runs the UIKit simulator harness. The workflow builds and delivers only real arm64e RootHide, with one deb.

Portable checks: `make check`, `make infra-check`, `python3 tools/test-local.py`.
Native checks: `make smoke`, `bash tools/run-ci-simulator.sh`, `make build ARCH=arm64e`, `make verify`.

Final debs are re-extracted and checked for exact installation layout, entry/resource uniqueness, original Metal output, actual CPU subtype, dependency binding, hashes and strict native signatures. The installer does not respring or terminate processes.

Simulator tests exercise original controls, real GPU pipelines and synthetic Dock views. They are not physical-device SpringBoard or real HID/XCUITest validation. Device appearance, compositor texture mapping, third-party tweak compatibility and performance still require on-device testing. Never treat a successful compile as proof of those outcomes.
