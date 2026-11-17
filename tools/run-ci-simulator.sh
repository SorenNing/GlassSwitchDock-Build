#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/simulator-runtime
xcrun simctl list devices available --json > evidence/simulator-runtime/devices.json
DEVICE=$(python3 -c 'import json; j=json.load(open("evidence/simulator-runtime/devices.json")); d=[v for k,a in j["devices"].items() if "iOS" in k for v in a if v.get("isAvailable") and "iPhone" in v["name"]]; d.sort(key=lambda x:(x.get("state")!="Booted",x["name"])); assert d,"No available iOS iPhone simulator"; print(d[0]["udid"])')
if ! xcrun simctl list devices booted --json | python3 -c 'import json,sys; j=json.load(sys.stdin); sys.exit(0 if any(x["udid"]==sys.argv[1] for a in j["devices"].values() for x in a) else 1)' "$DEVICE"; then
  xcrun simctl boot "$DEVICE"
fi
xcrun simctl bootstatus "$DEVICE" -b
bash tests/run-simulator.sh --app build/simulator/GlassSwitchDockHarness.app --device "$DEVICE" --output evidence/simulator-runtime
