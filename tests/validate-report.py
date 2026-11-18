#!/usr/bin/env python3
"""Fail closed on native assertions, incomplete scenarios or missing PNG evidence."""
import argparse
import json
from pathlib import Path
import sys

SWITCH = ('original_identity','original_defaults','original_size_63x28','initial_sync_silent',
          'user_tap_exactly_one_native_event','unrelated_controls_unchanged',
          'drag_commits_exactly_one_native_event','disabled_ignores_user_input','reenabled',
          'reenable_detaches_old_preserves_state','refresh_is_idempotent',
          'reparent_removes_old_sibling','source_detach_removes_overlay',
          'disable_restores_native_state','restore_saved_nondefault_host_properties')
DOCK = ('actual_original_material','clear_optics_with_neutral_side_band','container_geometry_only',
        'side_band_darkening_removed','actual_metal_backend_no_fallback','material_has_no_labels_sliders_or_touch_interception',
        'dock_icon_hit_test_preserved','backdrop_change_changes_real_gpu_pixels','refresh_idempotent',
        'wallpaper_only_valid_frame','server_wallpaper_fixture','initial_failure_retains_native_background','transient_failure_retains_last_good_frame','layout_burst_capture_budget','unchanged_pixels_skip_gpu_and_discovery','hidden_dock_skips_wallpaper_capture')

def validate(path):
    path = Path(path); report = json.loads(path.read_text()); errors = []
    if report.get('schema') != 1: errors.append('wrong report schema')
    if report.get('status') != 'passed' or report.get('failures') != 0: errors.append('native suite reports failures')
    env = report.get('environment',{})
    if env.get('hardwareProof') is not False: errors.append('native report must not claim hardware proof')
    if env.get('kind') != 'iOS Simulator UIKit application': errors.append('wrong execution environment')
    checks = report.get('checks',[]); ids = [v.get('id') for v in checks]; present = set(ids)
    if len(present) != len(ids): errors.append('duplicate assertion ids')
    errors.extend('failed assertion: '+str(v.get('id')) for v in checks if v.get('passed') is not True)
    required = {'environment.simulator_only','preferences.isolated_test_path', 'theseus.original_global_defaults',
                'theseus.no_global_style_quality_or_accessibility_side_effects','resource.metal_device_required',
                'resource.theseus.load_original_metallib','resource.glassify.load_original_metallib',
                'resource.glassify.actual_shader_execution_readback','resource.glassify.actual_renderer_initializes'}
    for style in ('theseus',):
        required.update('switch.'+style+'.'+v for v in SWITCH)
        required.update('switch.'+style+'.programmatic_sync_'+str(i) for i in range(6))
        required.update('screenshot.switch.'+style+'.render_'+v for v in ('on','off'))
    required.add('switch.theseus.uiview_bridge_contract')
    for cls in ('SBDockView','SBFloatingDockPlatterView'):
        for style in ('theseusClear','glassifyProminentClear'):
            suffixes = DOCK if style=='theseusClear' else tuple(v for v in DOCK if v not in ('clear_optics_with_neutral_side_band','container_geometry_only','side_band_darkening_removed','actual_metal_backend_no_fallback'))+('exact_prominent_clear_config',)
            required.update('dock.'+cls+'.'+style+'.'+v for v in suffixes)
            required.add('screenshot.dock.'+cls+'.'+style+'.render')
        required.add('dock.'+cls+'.disable_restores_background')
    for missing in sorted(required-present): errors.append('missing required assertion: '+missing)
    def png(filename):
        target = path.parent/filename
        if Path(filename).name != filename: errors.append('unsafe evidence filename: '+filename); return
        if not target.is_file() or target.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n': errors.append('missing/invalid PNG: '+filename)
    for check in checks:
        evidence = check.get('evidence',{})
        if not isinstance(evidence,dict): continue
        if check.get('id','').startswith('screenshot.'): png(evidence.get('file',''))
        if check.get('id','').endswith('backdrop_change_changes_real_gpu_pixels'):
            for filename in evidence.get('files',[]): png(filename)
            before,after = evidence.get('before',{}),evidence.get('after',{})
            if not before.get('checksum') or before.get('checksum')==after.get('checksum'): errors.append('unchanged/missing GPU checksum: '+check['id'])
    return {'status':'failed' if errors else 'passed','assertions':len(checks),'errors':errors,
            'hardwareProof':False,'report':str(path)}

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('report',type=Path); args=parser.parse_args()
    try: result=validate(args.report)
    except (ValueError,OSError,KeyError,TypeError) as error: result={'status':'failed','errors':[str(error)]}
    print(json.dumps(result,indent=2)); sys.exit(result['status']!='passed')
