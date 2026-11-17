#!/usr/bin/env python3
"""Portable regressions only; native UIKit results must come from tests/run-simulator.sh."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import time
import unittest

sys.dont_write_bytecode = True
ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'tests/evidence/local-report.json')
    args=parser.parse_args()
    started=time.time()
    suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'),pattern='test_*.py')
    log=io.StringIO(); result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
    inputs={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ('src','prefs','tests/Harness') for p in (ROOT/folder).rglob('*') if p.is_file()}
    report={'schema':1,'suite':'portable structural and native-report validation',
            'status':'passed' if result.wasSuccessful() else 'failed','testsRun':result.testsRun,
            'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),
            'started':started,'finished':time.time(),'environment':{'system':platform.system(),'python':platform.python_version()},
            'nativeUIKit':{'executed':False,'status':'not_run','reason':'Use the local macOS/Xcode simulator runner; portable checks are not native execution or hardware proof.'},
            'vendorManifestSHA256':hashlib.sha256((ROOT/'Vendor/manifest.json').read_bytes()).hexdigest(),
            'inputSHA256':inputs,'log':log.getvalue()}
    output=args.output.resolve()
    # This helper is scoped to tests; build infrastructure owns other evidence directories.
    if not output.is_relative_to(ROOT/'tests'): parser.error('--output must be under tests/')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(log.getvalue(),end='')
    print(json.dumps({k:v for k,v in report.items() if k not in ('inputSHA256','log')},indent=2))
    return not result.wasSuccessful()

if __name__=='__main__': sys.exit(main())
