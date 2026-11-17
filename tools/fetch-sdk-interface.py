#!/usr/bin/env python3
"""Fetch unmodified Preferences TBD from pinned original Theos SDK 16.5."""
import hashlib
import json
from pathlib import Path
import urllib.request
from project import ROOT

COMMIT = '0222fd5413cf4b9af096f37b4621afa2688572f7'
FILE = 'iPhoneOS16.5.sdk/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd'
DIGEST = '9daceaff6cf94346594a12f9ef9c2ea23de15475b516f9e33c20871a018c098b'
URL = 'https://raw.githubusercontent.com/theos/sdks/'+COMMIT+'/'+FILE
output = ROOT/'.toolchain/theos-sdks'/FILE
report = ROOT/'evidence/setup/sdk-interface.json'
report.parent.mkdir(parents=True, exist_ok=True)
result = {'url': URL, 'commit': COMMIT, 'expected_sha256': DIGEST}
try:
    if output.is_file() and hashlib.sha256(output.read_bytes()).hexdigest() == DIGEST:
        data = output.read_bytes()
    else:
        request = urllib.request.Request(URL, headers={'User-Agent': 'GlassSwitchDock-native-build'})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != DIGEST:
        raise ValueError('SDK original hash mismatch: '+actual)
    output.parent.mkdir(parents=True, exist_ok=True); output.write_bytes(data)
    result.update({'status': 'verified_original', 'sha256': actual, 'bytes': len(data), 'path': str(output)})
except Exception as e:
    # Explicit link remains strict with our audited minimal class interface.
    result.update({'status': 'fallback', 'error': str(e),
                   'path': 'packaging/stubs/Preferences.framework/Preferences.tbd'})
report.write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
