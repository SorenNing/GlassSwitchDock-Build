#!/usr/bin/env python3
"""Persist CI outcome; optional --gate exits according to persisted report."""
import argparse
import json
import os
from pathlib import Path
from project import ROOT

p = argparse.ArgumentParser(); p.add_argument('--gate', action='store_true'); args = p.parse_args()
output = ROOT/'evidence/ci-result.json'
if args.gate:
    result = json.loads(output.read_text())
else:
    keys = ['SETUP_RESULT', 'SOURCE_RESULT', 'INFRA_RESULT', 'ARM64E_RESULT', 'VERIFY_RESULT']
    if os.environ.get('REQUIRE_SIMULATOR', '').lower() == 'true':
        keys += ['SMOKE_RESULT', 'SIMULATOR_RESULT']
    steps = {key: os.environ.get(key, 'missing') for key in keys}
    result = {'status': 'passed' if all(v == 'success' for v in steps.values()) else 'failed', 'steps': steps}
    output.parent.mkdir(parents=True, exist_ok=True); output.write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['status'] == 'passed' else 1)
