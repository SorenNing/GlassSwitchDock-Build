#!/usr/bin/env python3
"""Run the real local UIKit harness; never performs a build or network call."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

COMMAND_OUTPUT = None
COMMAND_INDEX = 0

def command(args, *, env=None, check=True, timeout=60):
    global COMMAND_INDEX
    COMMAND_INDEX += 1
    args = [str(v) for v in args]
    print('SIMULATOR COMMAND:', args, 'timeout:', timeout, flush=True)
    log_path = COMMAND_OUTPUT/f'command-{COMMAND_INDEX:02d}.log' if COMMAND_OUTPUT else None
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
    import tempfile
    error_path = log_path.with_suffix('.stderr.log') if log_path else None
    with (log_path.open('w+b') if log_path else tempfile.TemporaryFile()) as log, \
         (error_path.open('w+b') if error_path else tempfile.TemporaryFile()) as errors:
        proc = subprocess.Popen(args, stdout=log, stderr=errors, env=env, start_new_session=True)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Terminate the whole command group, including any stuck simctl child.
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=5)
            log.flush(); log.seek(0); errors.flush(); errors.seek(0)
            print(log.read().decode('utf-8', 'replace')[-6000:], flush=True)
            print(errors.read().decode('utf-8', 'replace')[-6000:], file=sys.stderr, flush=True)
            if COMMAND_OUTPUT:
                (COMMAND_OUTPUT/'command-timeout.json').write_text(json.dumps({'command':args,'timeout':timeout,'exit':proc.returncode},indent=2)+'\n')
            raise RuntimeError(f'Simulator command exceeded {timeout}s: {args[:4]}')
        log.flush(); log.seek(0); errors.flush(); errors.seek(0)
        output = log.read().decode('utf-8', 'replace')
        error = errors.read().decode('utf-8', 'replace')
    print(output[-6000:], end='', flush=True)
    print(error[-6000:], end='', file=sys.stderr, flush=True)
    result = subprocess.CompletedProcess(args, proc.returncode, output, error)
    if check and result.returncode:
        raise RuntimeError(f'{args[0:4]} failed ({result.returncode}): {error[-6000:]}')
    return result

def main():
    global COMMAND_OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT/'build/simulator/GlassSwitchDockHarness.app')
    parser.add_argument('--device', default='booted', help='auto, booted, or explicit simulator UDID (no physical devices)')
    parser.add_argument('--output', type=Path, default=ROOT/'evidence/native-regression')
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    COMMAND_OUTPUT = output
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
    (output/'devices.json').write_text(json.dumps(available,indent=2)+'\n')
    devices = [d for runtime,group in available['devices'].items() if 'iOS' in runtime for d in group if d.get('isAvailable', True)]
    if args.device == 'auto':
        iphones = sorted((d for d in devices if 'iPhone' in d['name']), key=lambda d:(d['state']!='Booted',d['name']))
        if not iphones: parser.error('No available iPhone simulator')
        args.device = iphones[0]['udid']
    if args.device == 'booted':
        booted = [d for d in devices if d['state']=='Booted']
        if len(booted) != 1: parser.error('Use --device UDID when zero or multiple simulators are booted')
        device = booted[0]['udid']
    else:
        match = next((d for d in devices if d['udid']==args.device), None)
        if match is None: parser.error('--device must be an available iOS Simulator UDID')
        device = match['udid']
        if match['state'] != 'Booted': command(['xcrun','simctl','boot',device])
    command(['xcrun','simctl','bootstatus',device,'-b'], timeout=240)
    command(['xcrun','simctl','install',device,app], timeout=120)
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
