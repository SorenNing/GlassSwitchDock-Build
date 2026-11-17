#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# All simctl commands, including discovery and boot, are bounded and logged.
exec python3 -u tests/run-simulator.py --app build/simulator/GlassSwitchDockHarness.app --device auto --output evidence/simulator-runtime
