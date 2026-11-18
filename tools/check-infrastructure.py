#!/usr/bin/env python3
"""Portable infrastructure tests. Synthetic Mach-O fixtures never claim native builds."""
import gzip
import io
import json
import os
from pathlib import Path
import struct
import tarfile
import tempfile
from project import ROOT, CONFIG, vendor_manifest
import mkdeb
from verify import ar_read, tar_read, macho


def fixture(subtype=0x80000002, symbol='_objc_msgSend', ordinal=1):
    def dylib(name, command=0xc):
        s = name.encode()+b'\0'
        size = (24+len(s)+7)//8*8
        return struct.pack('<6I',command,size,24,0,0x10000,0x10000)+s+b'\0'*(size-24-len(s))
    commands = [dylib('/usr/lib/libobjc.A.dylib'),
                struct.pack('<6I',0x32,24,2,0xf0000,0xf0000,0)]
    ncmds = 4
    size = sum(map(len, commands))+24+16
    offset = 32+size
    strings = b'\0'+symbol.encode()+b'\0'
    sym = struct.pack('<IBBHQ',1,1,0,ordinal<<8,0)
    commands += [struct.pack('<6I',2,24,offset,1,offset+16,len(strings)),
                 struct.pack('<4I',0x1d,16,offset+16+len(strings),8)]
    return struct.pack('<8I',0xfeedfacf,0x100000c,subtype,6,ncmds,size,0x80,0)+b''.join(commands)+sym+strings+b'fixture!'


def rejects(fn):
    try:
        fn()
    except (ValueError, OSError, struct.error):
        return True
    raise AssertionError('Invalid fixture was accepted')


def tests():
    passed = []
    with tempfile.TemporaryDirectory(prefix='ng-infra-') as tmp:
        root = Path(tmp); stage = root/'stage'; (stage/'DEBIAN').mkdir(parents=True)
        (stage/'DEBIAN/control').write_text('Package: example\nVersion: 1\nArchitecture: all\n')
        (stage/'DEBIAN/postinst').write_text('#!/bin/sh\nexit 0\n'); (stage/'DEBIAN/postinst').chmod(0o755)
        payload = stage/'var/jb/Library/Application Support/GlassSwitchDock/GlassSwitchDockResources.bundle/GlassifyShaders.bundle'
        payload.mkdir(parents=True)
        (payload/'default.metallib').write_bytes(b'MTLB-fixture')
        p1,p2 = root/'one.deb',root/'two.deb'
        a,b = mkdeb.build(stage,p1,0),mkdeb.build(stage,p2,0)
        assert a['sha256'] == b['sha256']
        ar = ar_read(p1)
        files, meta = tar_read(ar['data.tar.gz'])
        assert len(files) == 1 and next(iter(files)).endswith('GlassifyShaders.bundle/default.metallib')
        ctl, _ = tar_read(ar['control.tar.gz'])
        assert set(ctl) == {'control','postinst','md5sums'}
        passed += ['deterministic ar/gzip/USTAR bytes', 'long nested resource path USTAR prefix', 'control md5sums coverage']
        bad = root/'bad.deb'; bad.write_bytes(p1.read_bytes()+b'garbage')
        rejects(lambda: ar_read(bad)); passed.append('trailing ar data rejected')
        evil = io.BytesIO()
        with tarfile.open(fileobj=evil,mode='w',format=tarfile.USTAR_FORMAT) as tar:
            m=tarfile.TarInfo('../escape'); m.size=1; tar.addfile(m,io.BytesIO(b'x'))
        rejects(lambda: tar_read(gzip.compress(evil.getvalue()))); passed.append('tar traversal rejected')
        link = stage/'badlink'; link.symlink_to('/etc/passwd')
        rejects(lambda: mkdeb.build(stage,root/'linked.deb')); passed.append('payload symlinks rejected')
        link.unlink()
    assert macho(fixture(), 'arm64e')['subtype'] == '0x80000002'
    assert macho(fixture(0), 'arm64')['subtype'] == '0x00000000'
    passed += ['real arm64e ABI subtype requirement', 'rootless arm64 subtype requirement']
    rejects(lambda: macho(fixture(2), 'arm64e')); passed.append('old arm64e ABI rejected')
    rejects(lambda: macho(fixture(0), 'arm64e')); passed.append('relabelled arm64 rejected')
    rejects(lambda: macho(fixture(ordinal=0xfe), 'arm64e')); passed.append('dynamic lookup imports rejected')
    rejects(lambda: macho(fixture(symbol='_MSHookMessageEx'), 'arm64e')); passed.append('direct MSHookMessageEx imports rejected')
    workflow = (ROOT/'.github/workflows/build.yml').read_text()
    assert 'workflow_dispatch:' in workflow and any('runs-on: '+label in workflow for label in ('macos-latest', 'macos-26-intel'))
    assert not any(x in workflow for x in ('  push:', '  pull_request:', '  schedule:'))
    assert 'if: ${{ always() }}' in workflow and 'dist/*.deb' in workflow and 'evidence/**' in workflow
    passed += ['manual-only macOS workflow', 'failure evidence upload configured']
    return passed


if __name__ == '__main__':
    result = {'status': 'failed', 'native_xcode_executed': False, 'synthetic_fixture_tests_only': True}
    try:
        result.update({'passed': tests(), 'status': 'passed'})
        try:
            result['vendor'] = vendor_manifest()
        except FileNotFoundError:
            result['vendor'] = {'status': 'awaiting_parent_sources'}
    except Exception as e:
        result.update({'status': 'failed', 'error': str(e)})
    output = ROOT/'evidence/infrastructure-check.json'; output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
    raise SystemExit(0 if result['status']=='passed' else 1)
