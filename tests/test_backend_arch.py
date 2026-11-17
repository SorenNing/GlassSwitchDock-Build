"""Backend process ABI coverage, independent from the deb architecture."""
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build import Build
from verify import backend_macho
spec=importlib.util.spec_from_file_location('ng_infra_fixture',ROOT/'tools/check-infrastructure.py')
infra=importlib.util.module_from_spec(spec);spec.loader.exec_module(infra)

def universal(parts):
    result=bytearray(8+20*len(parts));struct.pack_into('>II',result,0,0xcafebabe,len(parts))
    for i,(sub,data) in enumerate(parts):
        offset=(len(result)+15)//16*16;result.extend(b'\0'*(offset-len(result)))
        struct.pack_into('>5I',result,8+i*20,0x100000c,sub,offset,len(data),4);result.extend(data)
    return bytes(result)

class BackendABI(unittest.TestCase):
    def test_real_two_slice_coverage(self):
        data=universal([(0,infra.fixture(0)),(0x80000002,infra.fixture())])
        item=backend_macho(data,'arm64e')
        self.assertEqual(item['architectures'],['arm64','arm64e'])
        self.assertEqual({x['subtype'] for x in item['slices']},{'0x00000000','0x80000002'})
        self.assertEqual(backend_macho(infra.fixture(0),'arm64')['subtype'],'0x00000000')

    def test_old_thin_or_mislabeled_or_corrupt_backend_is_rejected(self):
        valid=universal([(0,infra.fixture(0)),(0x80000002,infra.fixture())])
        overlap=bytearray(valid);first=struct.unpack_from('>I',overlap,16)[0];struct.pack_into('>I',overlap,36,first)
        corrupt=[infra.fixture(),infra.fixture(0),valid[:-1],bytes(overlap),
                 universal([(0,infra.fixture(0)),(0,infra.fixture(0))]),
                 universal([(0,infra.fixture(0)),(2,infra.fixture(2))]),
                 universal([(0,infra.fixture(0)),(0x80000002,infra.fixture(0))])]
        for data in corrupt:
            with self.subTest(length=len(data)):
                with self.assertRaises(ValueError):backend_macho(data,'arm64e')

    def test_build_keeps_roothide_scheme_for_arm64_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            b=Build.__new__(Build);b.out=Path(tmp);b.obj=b.out/'obj';b.obj.mkdir()
            b.arch='arm64e';b.target='arm64e-apple-ios15.0';b.sdk='/fixture-sdk'
            b.smoke=False;b.variant='arm64e';b.defines=['-DNG_ROOTHIDE=1','-DTHEOS_PACKAGE_SCHEME_ROOTHIDE=1']
            b.ccbase=['-target',b.target,'-isysroot',b.sdk]
            b.src={'render':[Path('render/NGDockRegister.mm')],'cpp':[Path('engine.cpp')]}
            compiled=[];commands=[]
            def compile_sources(sources):
                compiled.append((b.arch,b.target,b.obj,list(b.defines),list(b.ccbase),sources));return [b.obj/'real.o']
            b.compile=compile_sources;b.tool=lambda name:['xcrun',name];b.run=lambda cmd:commands.append([str(x) for x in cmd])
            original=(b.arch,b.target,b.obj,list(b.ccbase));b.backend()
            self.assertEqual([x[0] for x in compiled],['arm64','arm64e'])
            self.assertEqual([x[1] for x in compiled],['arm64-apple-ios15.0','arm64e-apple-ios15.0'])
            self.assertEqual(len({x[2] for x in compiled}),2)
            for x in compiled:
                self.assertIn('-DNG_ROOTHIDE=1',x[3]);self.assertEqual(x[4][1],x[1])
            links=[x for x in commands if '-dynamiclib' in x]
            self.assertEqual(len(links),2)
            for cmd in links:self.assertIn('-Wl,-needed-lroothide',cmd)
            self.assertEqual(sum('-create' in x for x in commands),1)
            self.assertTrue(any('--all-architectures' in x and '--strict' in x for x in commands))
            self.assertEqual((b.arch,b.target,b.obj,b.ccbase),original)
