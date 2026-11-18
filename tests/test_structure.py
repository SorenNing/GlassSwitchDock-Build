#!/usr/bin/env python3
"""Portable source contracts. These checks do not claim native UIKit execution."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PINNED = {'Theseus':'71ca1c127a4e7fe3387361f160c4890dbd427f66',
          'Glassify':'a8e52aa9c015502fb68d5f81687698f11df6977d'}
KEYS = {'enabledSwitch','enabledDock','dockStyle'}

def text(path): return (ROOT/path).read_text()
def specs():
    data=plistlib.loads((ROOT/'prefs/Resources/Root.plist').read_bytes())
    return data if isinstance(data,list) else data.get('items',data.get('PreferenceSpecifiers',[]))
def manifest():
    data=json.loads(text('Vendor/manifest.json')); data=data.get('files',data)
    if isinstance(data,list): data={v['path']:v['sha256'] for v in data}
    return {('Vendor/'+p if not p.startswith('Vendor/') else p):(v['sha256'] if isinstance(v,dict) else v) for p,v in data.items()}

class Structure(unittest.TestCase):
    def test_vendor_revisions_and_complete_byte_identity(self):
        hashes=manifest(); files={p.relative_to(ROOT).as_posix() for name in PINNED for p in (ROOT/'Vendor'/name).rglob('*') if p.is_file() and p.name!='.DS_Store'}
        metadata={'Vendor/'+name+'/UPSTREAM.json' for name in PINNED}
        self.assertEqual(set(hashes)-metadata,files-metadata,'manifest must cover complete original distributions')
        for name,pin in PINNED.items():
            self.assertEqual(json.loads(text('Vendor/'+name+'/UPSTREAM.json'))['revision'],pin)
        for path,digest in hashes.items():
            with self.subTest(path=path): self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),digest)
        self.assertEqual(len(list((ROOT/'Vendor/Theseus/Sources').rglob('*.swift'))),33)
        self.assertEqual(len(list((ROOT/'Vendor/Theseus/Sources').rglob('*.metal'))),1)
        self.assertEqual(len(list((ROOT/'Vendor/Glassify/Sources/Glassify/Core').glob('*.cpp'))),4)
        self.assertEqual(len(list((ROOT/'Vendor/Glassify/Sources/Glassify/Platform').glob('*.mm'))),16)
    def test_exactly_three_settings_one_domain(self):
        values=[s for s in specs() if s.get('key')]
        self.assertEqual(len(values),3); self.assertEqual({s['key'] for s in values},KEYS)
        self.assertEqual({s['defaults'] for s in values},{'com.ning.glassswitchdock'})
        for spec in values:
            with self.subTest(key=spec['key']):
                if spec['key'].endswith('Style'):
                    self.assertEqual(spec.get('validValues',spec.get('values')),[0,1])
                    self.assertEqual(spec['default'],0)
                    self.assertEqual(len(spec.get('validTitles',spec.get('titles',[]))),2)
                else: self.assertEqual(spec['cell'],'PSSwitchCell'); self.assertIs(spec['default'],True)
        self.assertEqual(len(list((ROOT/'prefs/Resources').glob('entry.plist'))),1)
        info=plistlib.loads((ROOT/'prefs/Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleExecutable'],'GlassSwitchDockPrefs')
    def test_original_control_bridge_and_no_parameter_overrides(self):
        bridge=text('src/TheseusBridge.swift')
        self.assertRegex(bridge,r'class\s+NGTheseusSwitch\s*:\s*UIView')
        self.assertRegex(bridge,r'\bTheseusSwitch\s*\(')
        switch=bridge.split('@objc(NGClearDockView)')[0]
        self.assertNotRegex(switch,r'\.(?:layout|glassMaterial|onTintColor|offTintColor|thumbTintColor)\s*(?:\.[A-Za-z]+\s*)?=')
        self.assertIn('toggle.onValueChanged',switch); self.assertIn('setOn:animated:',switch)
        self.assertIn('TheseusConfiguration.clear',bridge)
        core='\n'.join(p.read_text() for p in (ROOT/'src').glob('*') if p.suffix in {'.m','.mm','.swift','.h'})
        self.assertNotRegex(core,r'glassStyle\s*=\s*\.iOS26|iosVersionOverride\s*=|tierOverride\s*=|refractionQualityOverride\s*=')
        self.assertNotRegex(core,r'UIFont|setFont:|\.font\s*=|\bappearance\s*\]|UIAppearance|DNToggleView|daynight')
        self.assertNotIn('GLSSwitch',text('src/NGSwitch.m'))
        self.assertNotIn('NGSwitchStyle',text('src/Bridge.h'))
    def test_material_defaults_and_no_demo_controls(self):
        dock=text('src/NGDock.mm')
        self.assertIn('GLSGlassStyleClear',dock); self.assertIn('UIColor.secondarySystemFillColor',dock)
        self.assertNotRegex(dock,r'GLSGlassButton\s*\*|UILabel|UISlider|GLSSlider|TheseusSlider|setTitle:|\.font\s*=')
        self.assertRegex(dock,r'userInteractionEnabled\s*=\s*NO')
        self.assertRegex(dock,r'isAccessibilityElement\s*=\s*NO')
        self.assertNotRegex(dock,r'blurLodBias\s*=|frost\s*=|adaptsColorScheme\s*=')
    def test_runtime_resource_and_test_isolation_contract(self):
        bridge=text('src/Bridge.h')
        for function in ('NGRefreshSwitch','NGRemoveSwitch','NGSyncSwitch','NGRefreshDock','NGRemoveDock','NGRefreshDocks','NGPreferencesReload','NGStorePreference','NGBundleResources','NGBundleGlassify'):
            self.assertIn(function+'(',bridge)
        resources=text('src/NGResources.m')
        self.assertIn('GlassSwitchDockResources.bundle',resources); self.assertIn('GlassifyShaders.bundle',resources)
        self.assertRegex(resources,r'(?s)#if(?:n?def|\s+).*?NG_TESTING.*?NG_TEST_PREFS')
        self.assertIn('NGBundleGlassify',text('src/resource_bundle_accessor.h'))
        tweak=text('src/Tweak.m')
        self.assertRegex(tweak,r'(?s)#ifndef NG_TESTING\s*__attribute__\s*\(\(constructor\)\)')
    def test_harness_uses_original_actions_not_callback_fakes(self):
        probe=text('tests/Harness/NGTheseusProbe.swift'); fixture=text('tests/Harness/NGHarness.m')
        for value in ('control.accessibilityActivate()','control.scriptedTouchBegan','control.scriptedTouchMoved','control.scriptedTouchEnded','glass.captureSnapshot'):
            self.assertIn(value,probe)
        for value in ('NGStorePreference',):
            self.assertIn(value,fixture)
        self.assertNotRegex(probe+fixture,r'\.onChanged\?\(|setOnChanged:|onValueChanged\?\(')
        for name in ('main.m','NGSwitchTests.m','NGDockTests.m','NGResourceTests.m','NGTheseusProbe.swift'):
            self.assertTrue((ROOT/'tests/Harness'/name).is_file())
        self.assertIn('actual_shader_execution_readback',text('tests/Harness/NGResourceTests.m'))
        self.assertIn('backdrop_change_changes_real_gpu_pixels',text('tests/Harness/NGDockTests.m'))

if __name__=='__main__': unittest.main()
