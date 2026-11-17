import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('native_report_validator',Path(__file__).with_name('validate-report.py'))
validator=importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)

class ReportValidation(unittest.TestCase):
    def verify(self, report):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'report.json'; path.write_text(json.dumps(report)); return validator.validate(path)
    def test_empty_pass_report_is_rejected(self):
        result=self.verify({'schema':1,'status':'passed','failures':0,'checks':[],
                            'environment':{'kind':'iOS Simulator UIKit application','hardwareProof':False}})
        self.assertEqual(result['status'],'failed')
        self.assertTrue(any('missing required assertion' in v for v in result['errors']))
    def test_failed_assertion_overrides_summary(self):
        result=self.verify({'schema':1,'status':'passed','failures':0,'checks':[{'id':'native.failure','passed':False}]})
        self.assertIn('failed assertion: native.failure',result['errors'])
    def test_duplicate_and_missing_screenshot_rejected(self):
        check={'id':'screenshot.a','passed':True,'evidence':{'file':'absent.png'}}
        result=self.verify({'schema':1,'status':'passed','failures':0,'checks':[check,check]})
        self.assertIn('duplicate assertion ids',result['errors'])
        self.assertIn('missing/invalid PNG: absent.png',result['errors'])
    def test_unchanged_gpu_output_rejected(self):
        check={'id':'dock.x.backdrop_change_changes_real_gpu_pixels','passed':True,
               'evidence':{'before':{'checksum':'123'},'after':{'checksum':'123'},'files':[]}}
        result=self.verify({'schema':1,'status':'passed','failures':0,'checks':[check]})
        self.assertTrue(any('unchanged/missing GPU checksum' in v for v in result['errors']))

if __name__=='__main__': unittest.main()
