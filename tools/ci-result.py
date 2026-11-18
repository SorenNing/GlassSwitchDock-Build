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
    try:
        result = json.loads(output.read_text())
    except (OSError, ValueError) as error:
        result = {'status': 'failed', 'error': str(error), 'report': str(output.relative_to(ROOT))}
    print('Persisted CI report:', str(output.relative_to(ROOT)), flush=True)
else:
    keys = ['SETUP_RESULT', 'SOURCE_RESULT', 'INFRA_RESULT', 'ARM64E_RESULT', 'VERIFY_RESULT']
    if os.environ.get('REQUIRE_SIMULATOR', '').lower() == 'true':
        keys += ['SMOKE_RESULT', 'SIMULATOR_RESULT']
    steps = {key: os.environ.get(key, 'missing') for key in keys}
    result = {'status': 'passed' if all(v == 'success' for v in steps.values()) else 'failed', 'steps': steps}
    output.parent.mkdir(parents=True, exist_ok=True); output.write_text(json.dumps(result, indent=2)+'\n')
    # Publish only allowlisted statuses and assertion identifiers, never raw logs,
    # paths, device identifiers or environment values.
    summary = ['## Native regression outcome', '', '| Stage | Outcome |', '| --- | --- |']
    allowed = {'success', 'failure', 'cancelled', 'skipped', 'missing'}
    summary += [f'| {key} | {value if value in allowed else "unknown"} |' for key, value in steps.items()]
    report_path = ROOT/'evidence/simulator-runtime/report.json'
    try:
        native = json.loads(report_path.read_text())
        checks = native.get('checks', [])
        summary += ['', f'Native report present; assertions: {len(checks)}.']
        for check in checks:
            identifier = check.get('id', '')
            if check.get('passed') is not True and isinstance(identifier, str):
                safe = ''.join(c for c in identifier if c.isascii() and (c.isalnum() or c in '._-'))[:180]
                summary.append(f'- Failed assertion: `{safe}`')
                print(f'::error title=Native assertion failed::{safe}', flush=True)
                if safe in {
                    'dock.SBDockView.staticProminent.real_gpu_rgba_without_black_backing',
                    'dock.SBFloatingDockPlatterView.staticProminent.real_gpu_rgba_without_black_backing',
                }:
                    evidence = check.get('evidence', {})
                    if isinstance(evidence, dict):
                        fields = []
                        for key in ('bytes', 'transparent', 'translucent', 'colored', 'minAlpha', 'maxAlpha'):
                            value = evidence.get(key)
                            if type(value) is int and 0 <= value <= 2**53:
                                fields.append(f'{key}={value}')
                        if fields:
                            details = ', '.join(fields)
                            summary.append(f'  - Pixel evidence: {details}')
                            print(f'::error title=Native pixel evidence::{safe}: {details}', flush=True)
    except (OSError, ValueError, TypeError):
        summary += ['', 'Native report absent or unreadable: failure occurred before a complete report was collected.']
        print('::error title=Native report unavailable::No complete simulator report was collected.', flush=True)
    destination = os.environ.get('GITHUB_STEP_SUMMARY')
    if destination:
        with open(destination, 'a') as stream:
            stream.write('\n'.join(summary)+'\n')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['status'] == 'passed' else 1)
