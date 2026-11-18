# Build and validation

This repository requires macOS and full Xcode (Swift and Metal). The on-device
host has no xcodebuild or xcrun; portable checks do not establish compilation.

- `make check`: source inventory and all 89 pinned Vendor files.
- `make infra-check`: packaging/ABI and workflow contracts.
- `python3 tools/test-local.py`: portable regression checks, including generated compatibility sources.
- `make smoke`: compile the actual-source simulator harness on macOS.
- `bash tools/run-ci-simulator.sh`: execute native simulator regressions.
- `make build ARCH=arm64e`: build RootHide on macOS.
- `make verify`: verify final package ABI and signatures.

The workflow in .github/workflows/build.yml runs on pushes to main and manual
dispatch. Push builds require simulator regressions. Inspect all stage outcomes
and the final gate. A produced
package alone does not prove the simulator passed.

Keep Vendor files byte-identical. tools/theseus_compat.py creates generated
Swift copies under the build directory. Exact-match guards reject changed
upstream anchors. Production and simulator compilation use the same copies.
Keep control and packaging/config.json versions in sync for each package build.

Dock GPU readiness waits must return to the main dispatch queue between polls.
Do not use a nested RunLoop from a main-queue block: Metal publishes its result
on that same queue, which cannot drain until the block returns. Keep all four
Dock scenarios and their real GPU assertions mandatory.

Simulator execution does not establish physical SpringBoard rendering or real
touch behavior. Device installation and visual/gesture checks are separate.
