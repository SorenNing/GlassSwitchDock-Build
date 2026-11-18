# GlassSwitchDock build and validation

This repository builds with macOS and full Xcode, including Swift and Metal.
The jailbroken iPhone authoring host cannot run this native build: it has no
xcodebuild or xcrun. Do not install Theos or substitute structural checks for
native compilation.

- `make check`: verify source inventory and all 89 pinned vendor files.
- `make infra-check`: packaging/ABI and workflow contract checks.
- `python3 tools/test-local.py`: portable production regression contracts.
  Device-built C fixtures are signed with ldid and tests/Tool.entitlements
  before execution when ldid is available.
- `make smoke`: compile the actual-source simulator harness on macOS.
- `bash tools/run-ci-simulator.sh`: execute the simulator regression harness.
- `make build ARCH=arm64e`: build the RootHide package on macOS.
- `make verify`: inspect final package contents, ABI slices and signatures.

The Native GlassSwitchDock workflow runs on pushes and pull requests targeting
main, and supports manual dispatch. Automatic runs require both simulator
checks and package verification. Inspect every stage and the final gate; a
package alone does not mean all tests passed. Artifacts include packages,
checksums, metadata, and failure evidence.

Keep Vendor files byte-identical. tools/theseus_compat.py creates patched Swift
inputs only in the generated build directory. Update compatibility patches
with exact-match guards whenever the pinned source changes.

Increment control and packaging/config.json versions together for each new
package build. Current package identifier is com.ning.glassswitchdock.

Simulator results do not establish physical SpringBoard Dock rendering or
real touch behavior. Device installation and verification are separate steps.
