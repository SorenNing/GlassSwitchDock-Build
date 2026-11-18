#!/usr/bin/env python3
"""Run the real local UIKit harness; never performs a build or network call."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

def command(args, *, env=None, check=True):
    result = subprocess.run([str(v) for v in args], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env)
    if check and result.returncode:
        raise RuntimeError(f'{args[0:4]} failed ({result.returncode}): {result.stderr[-6000:]}')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT/'build/simulator/GlassSwitchDockHarness.app')
    parser.add_argument('--device', default='booted', help='Booted simulator or explicit UDID (no physical devices)')
    parser.add_argument('--output', type=Path, default=ROOT/'evidence/native-regression')
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    if platform.system() != 'Darwin' or not shutil.which('xcrun'):
        parser.error('Native execution requires local macOS + full Xcode + iOS Simulator. No native tests executed.')
    app = args.app.resolve()
    info_path = app/'Info.plist'
    if not info_path.is_file(): parser.error(f'Build the UIKit .app first: {app}')
    info = plistlib.loads(info_path.read_bytes())
    bundle_id = info['CFBundleIdentifier']
    if bundle_id != 'com.minis.GlassSwitchDockHarness': parser.error('Refusing to replace a non-harness app')
    if args.timeout <= 0 or args.timeout > 600: parser.error('--timeout must be in (0, 600]')
    for bundle in (app/'GlassSwitchDockResources.bundle', app/'GlassSwitchDockResources.bundle/GlassifyShaders.bundle'):
        if not (bundle/'default.metallib').is_file(): parser.error(f'Missing original compiled shader resource: {bundle}')
    available = json.loads(command(['xcrun','simctl','list','devices','available','--json']).stdout)
    devices = [d for group in available['devices'].values() for d in group if d.get('isAvailable', True)]
    if args.device == 'booted':
        booted = [d for d in devices if d['state']=='Booted']
        if len(booted) != 1: parser.error('Use --device UDID when zero or multiple simulators are booted')
        device = booted[0]['udid']
    else:
        match = next((d for d in devices if d['udid']==args.device), None)
        if match is None: parser.error('--device must be an available iOS Simulator UDID')
        device = match['udid']
        if match['state'] != 'Booted': command(['xcrun','simctl','boot',device])
    command(['xcrun','simctl','bootstatus',device,'-b'])
    command(['xcrun','simctl','install',device,app])
    container = Path(command(['xcrun','simctl','get_app_container',device,bundle_id,'data']).stdout.strip())
    sandbox_output = container/'Documents/NGRegression'
    sandbox_output.mkdir(parents=True, exist_ok=True)
    # Prevent a prior successful run from satisfying the polling loop.
    stale = sandbox_output/'report.json'
    if stale.exists(): stale.unlink()
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    root_plist = plistlib.loads((ROOT/'prefs/Resources/Root.plist').read_bytes())
    specs = root_plist if isinstance(root_plist,list) else root_plist.get('items',root_plist.get('PreferenceSpecifiers',[]))
    domains = {s['defaults'] for s in specs if s.get('key')}
    if len(domains) != 1: parser.error('Expected exactly one preference domain')
    env = dict(os.environ)
    env['SIMCTL_CHILD_NG_TEST_PREFS_DOMAIN'] = domains.pop()
    env['SIMCTL_CHILD_NG_TEST_OUTPUT'] = str(sandbox_output)
    env['SIMCTL_CHILD_NG_TEST_PREFS'] = str(container/'tmp/NGRegression-preferences.plist')
    command(['xcrun','simctl','terminate',device,bundle_id], check=False)
    launch = command(['xcrun','simctl','launch','--terminate-running-process',
                      '--stdout='+str(output/'stdout.log'),'--stderr='+str(output/'stderr.log'),device,bundle_id], env=env)
    (output/'launch.txt').write_text(launch.stdout+launch.stderr)
    deadline = time.monotonic()+args.timeout
    while not stale.is_file():
        if time.monotonic() >= deadline:
            (output/'runner-error.json').write_text(json.dumps({'status':'failed','reason':'timeout or crash before report', 'nativeExecuted':True,'timeoutSeconds':args.timeout},indent=2)+'\n')
            command(['xcrun','simctl','io',device,'screenshot',output/'timeout-screen.png'],check=False)
            command(['xcrun','simctl','terminate',device,bundle_id],check=False)
            raise RuntimeError('Harness timed out/crashed before producing report.json; inspect stdout.log and stderr.log')
        time.sleep(0.25)
    for path in sandbox_output.iterdir():
        if path.is_file(): shutil.copy2(path,output/path.name)
    command(['xcrun','simctl','io',device,'screenshot',output/'simulator-screen.png'])
    command(['xcrun','simctl','terminate',device,bundle_id],check=False)
    result = command([sys.executable,HERE/'validate-report.py',output/'report.json'],check=False)
    print(result.stdout,end=''); print(result.stderr,end='',file=sys.stderr)
    return result.returncode

if __name__ == '__main__':
    try: sys.exit(main())
    except (RuntimeError,ValueError,KeyError,OSError) as error:
        print(f'Native regression failed: {error}',file=sys.stderr); sys.exit(1)
