# Own Dock render-server transport

This change replaces the Dock's UIKit capture path with a self-built, two-process texture transport. It keeps this project's Dock locator (`NGDockBackground`), settings, icon layout, Theseus Clear/Glassify Clear material sources, and original Theseus switch. It does not embed SystemBox/Hang libraries, use their material matcher, install identity checks, filter names, shader, or preference domain.

## Runtime

- Frontend `src/NGDock.mm`: the existing Dock background getter/ivar locator is retained byte-for-byte. A noninteractive `NGSystemBackdrop` is inserted at the existing background position. The native background remains visible until an accepted parameter packet has produced a successful GPU frame. Failure detaches the filter and restores native background alpha.
- `src/NGSystemBackdrop.mm`: a `CABackdropLayer`, own filter namespace `com.ning.glassswitchdock.dock.<slot>`, no screenshot or timer loop. Parameter publications are atomic, tokened and deduplicated only after success. Runtime state uses the shared `src/NGDockStatePath.h` policy. The logical path `/var/mobile/Library/Preferences/com.ning.glassswitchdock.render` is converted through the real RootHide `jbroot(const char *)` interface in both production processes. Failed conversion stops publication instead of selecting another namespace. The backend records its loaded process and resolved state path in `load.plist`; final RootHide package verification requires both frontend and backend to import `_jbroot` from libroothide.
- Self-built `GlassSwitchDockRender.dylib`: `render/NGDockRegister.mm` resolves QuartzCore's Gaussian render registration and intercepts only this project's filter atoms. Other atoms delegate to the previous implementation. Installation is one-shot, version-gated to iOS 15–18 and protected against repeated rapid backboardd starts. This is a private ABI, not a public compatibility guarantee.
- `render/NGRenderResolver.mm`: source implementation adapted from our existing Feature resolver, in its own namespace. It reads the loaded QuartzCore image and never loads the reference tweak.
- `render/NGDockGPU.mm`: uses CA's input/output textures and command buffer. Existing Theseus/Glassify shaders perform the material rendering. Intermediate textures have exclusive frame leases until GPU completion. A separate transport shader handles texture-format sampling only.
- `src/NGDockMaterialParameters.swift`: exports the existing Theseus Clear uniform construction without starting a renderer or capturing a view. The previously shipped Dock-only `bandBias = 0` setting is retained. Switch source and all 89 vendor inputs are unchanged.

## Validation limits

Local Apple-SDK Clang syntax checks and portable regressions cannot validate Apple Swift/Metal compilation, real SpringBoard/backboardd texture layout, renderer ABI, CA filter propagation, visual quality, power consumption, or performance. The native simulator harness exercises our actual encoder with synthetic Metal textures and preserves the independent switch tests. It does not run backboardd hooks or establish physical-device compatibility.

The current transport requires source/destination textures to match the published surface extent. Unknown/padded layouts are rejected and restore the native background instead of inventing a crop transform. This condition remains to be confirmed on device. No claim of complete runtime equivalence, pixel identity to previous capture rendering, or flicker-free operation is made.

The package remains one deb and one settings entry. It contains one frontend and our independently compiled render backend, both signed for the selected ABI. Installation provisions only the mobile-owned runtime state directory and does not respring or signal any process.
