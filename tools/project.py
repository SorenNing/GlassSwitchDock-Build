#!/usr/bin/env python3
"""Shared source discovery, immutable-vendor and preference contracts."""
import hashlib
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'packaging/config.json').read_text())
KEYS = {'enabledSwitch', 'enabledDock', 'dockStyle'}
PREF_NAME = re.compile(r'PrefsController|PreferencesController|RootListController', re.I)
LEGACY = re.compile(r'DNToggleView|daynight|\bsun\b|\bmoon\b', re.I)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def discover():
    theseus = ROOT / 'Vendor/Theseus'
    glassify = ROOT / 'Vendor/Glassify'
    swift = sorted(theseus.rglob('*.swift'))
    swift = [p for p in swift if 'Sources' in p.parts and 'Tests' not in p.parts]
    gsrc = glassify / 'Sources/Glassify'
    explicit = ROOT / 'packaging/sources.json'
    opts = json.loads(explicit.read_text()) if explicit.exists() else {}
    prefs = sorted(set([*ROOT.glob('prefs/*.m'), *ROOT.glob('prefs/*.mm'),
                        *(ROOT / p for p in opts.get('preference_sources', []))]))
    core = []
    for p in sorted([*ROOT.glob('src/*.m'), *ROOT.glob('src/*.mm')]):
        text = p.read_text()
        if p in prefs or PREF_NAME.search(p.name) or re.search(r'@interface\s+\w+\s*:\s*PSListController', text):
            if p not in prefs:
                prefs.append(p)
        else:
            core.append(p)
    return {
        'vendor_swift': swift,
        'swift': swift + [ROOT / 'src/TheseusBridge.swift', ROOT / 'src/TheseusBundle.swift', ROOT / 'src/NGDockMaterialParameters.swift'],
        'render': sorted((ROOT / 'render').glob('*.mm')),
        'transport_metal': sorted((ROOT / 'render').glob('*.metal')),
        'core': core,
        'cpp': sorted((gsrc / 'Core').rglob('*.cpp')),
        'platform': sorted(p for p in (gsrc / 'Platform').rglob('*.mm') if p.name != 'GLSSwitch.mm'),
        'prefs': sorted(prefs),
        'theseus_metal': sorted(theseus.glob('Sources/**/*.metal')),
        'glassify_metal': sorted(gsrc.glob('Shaders/**/*.metal')),
        'gsrc': gsrc,
    }


def vendor_manifest():
    manifest = ROOT / 'Vendor/manifest.json'
    data = json.loads(manifest.read_text())
    items = data.get('files', data)
    if isinstance(items, list):
        items = {x['path']: x['sha256'] for x in items}
    if not isinstance(items, dict):
        raise ValueError('Vendor/manifest.json must contain a files map or list')
    hashes = {}
    for path, value in items.items():
        digest = value.get('sha256') if isinstance(value, dict) else value
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-fA-F]{64}', digest):
            raise ValueError('Invalid vendor digest: ' + path)
        path = path.removeprefix('./')
        if not path.startswith('Vendor/'):
            path = 'Vendor/' + path
        if '..' in Path(path).parts or Path(path).is_absolute():
            raise ValueError('Unsafe manifest path: ' + path)
        hashes[path] = digest.lower()
    actual = {rel(p) for name in ('Theseus', 'Glassify')
              for p in (ROOT / 'Vendor' / name).rglob('*')
              if p.is_file() and p.name not in ('.DS_Store', 'UPSTREAM.json')}
    # Parent-generated provenance metadata is not an original upstream source.
    actual |= {p for p in hashes if Path(p).name == 'UPSTREAM.json'}
    if actual != set(hashes):
        raise ValueError(f'Vendor coverage mismatch: missing={sorted(actual-set(hashes))}, stale={sorted(set(hashes)-actual)}')
    for path, digest in hashes.items():
        if sha256(ROOT / path) != digest:
            raise ValueError('Vendor original hash mismatch: ' + path)
    return {'files': len(hashes), 'manifest_sha256': sha256(manifest), 'verified': True}


def icon_source(name):
    candidates = [ROOT / 'assets/Icons' / name, ROOT / 'prefs/Resources' / name]
    if name == 'pkgicon.png':
        candidates = [ROOT / 'assets/pkgicon.png', ROOT / 'assets/Icons/icon.png', ROOT / 'prefs/Resources/icon.png']
    return next((p for p in candidates if p.is_file()), candidates[0])


def specifiers(path):
    doc = plistlib.loads(Path(path).read_bytes())
    values = doc if isinstance(doc, list) else doc.get('items', doc.get('PreferenceSpecifiers', []))
    specs = [v for v in values if isinstance(v, dict) and v.get('key')]
    if len(specs) != 3 or {v['key'] for v in specs} != KEYS:
        raise ValueError('Root.plist must have exactly three persisted keys: ' + ', '.join(sorted(KEYS)))
    for v in specs:
        key = v['key']
        if v.get('defaults') != CONFIG['package']:
            raise ValueError('Wrong preferences domain for ' + key)
        if key == 'dockStyle':
            if v.get('validValues', v.get('values')) != [0, 1] or v.get('cell') not in ('PSSegmentCell', 'PSLinkListCell'):
                raise ValueError('Style specifier must enumerate 0/1: ' + key)
        elif v.get('cell') != 'PSSwitchCell':
            raise ValueError('Enabled specifier must be PSSwitchCell: ' + key)
    return sorted(KEYS)


def check():
    sources = discover()
    counts = {k: len(v) for k, v in sources.items() if isinstance(v, list)}
    if counts['vendor_swift'] != 33 or counts['swift'] != 36:
        raise ValueError('Expected 33 original + 3 bridge/parameter Swift sources: ' + str(counts))
    if counts['cpp'] != 4 or counts['platform'] == 0 or counts['core'] == 0 or counts['prefs'] == 0:
        raise ValueError('Missing actual Glassify/runtime/preferences sources: ' + str(counts))
    if counts['render'] != 4 or counts['transport_metal'] != 1:
        raise ValueError('Missing own render backend / transport source: ' + str(counts))
    if counts['theseus_metal'] != 1 or counts['glassify_metal'] == 0:
        raise ValueError('Missing original Metal sources: ' + str(counts))
    for p in sources['swift'] + sources['core'] + sources['cpp'] + sources['platform'] + sources['prefs'] + sources['render']:
        if not p.is_file():
            raise ValueError('Missing source: ' + rel(p))
    for p in list(ROOT.glob('src/*')) + list(ROOT.glob('prefs/*')):
        if not p.is_file() or p.suffix.lower() not in ('.m', '.mm', '.h', '.swift', '.c', '.cpp'):
            continue
        if LEGACY.search(p.name) or LEGACY.search(p.read_text()):
            raise ValueError('Legacy implementation token in source: ' + rel(p))
    for p in (ROOT / 'src/Bridge.h', ROOT / 'src/resource_bundle_accessor.h', ROOT / 'src/Filter.plist'):
        if not p.is_file():
            raise ValueError('Missing parent interface: ' + rel(p))
    accessor = (ROOT / 'src/resource_bundle_accessor.h').read_text()
    if 'SWIFTPM_MODULE_BUNDLE' not in accessor or 'NGBundleGlassify' not in accessor:
        raise ValueError('Glassify resource accessor must select NGBundleGlassify')
    bridge = (ROOT / 'src/Bridge.h').read_text()
    if 'NGBundleResources' not in bridge:
        raise ValueError('Swift bridging header must declare NGBundleResources')
    exports = set(re.findall(r'FOUNDATION_EXPORT\s+[^;\n]*?\b(NG\w+)\s*\(', bridge))
    for source in sources['core']:
        declarations = set(re.findall(r'^static\s+(?!.*\(\*).*?\b(NG\w+)\s*\(', source.read_text(), re.M))
        conflicts = exports & declarations
        if conflicts:
            raise ValueError('Static hook conflicts with exported function in '+rel(source)+': '+', '.join(sorted(conflicts)))
    hooksrc = '\n'.join(p.read_text() for p in sources['core'])
    if 'MSHookMessageEx' in hooksrc and 'dlsym' not in hooksrc:
        raise ValueError('MSHookMessageEx must resolve at runtime via dlsym')
    for p in sources['core'] + sources['render']:
        text = p.read_text()
        if '__attribute__((constructor))' in text and 'NG_TESTING' not in text:
            raise ValueError('Constructor needs NG_TESTING guard for smoke: ' + rel(p))
    prefs = ROOT / 'prefs/Resources'
    specifiers(prefs / 'Root.plist')
    info = plistlib.loads((prefs / 'Info.plist').read_bytes())
    if info.get('CFBundleExecutable') != 'GlassSwitchDockPrefs':
        raise ValueError('Wrong preferences executable')
    entry = plistlib.loads((prefs / 'entry.plist').read_bytes())
    entry = entry.get('entry', entry)
    if entry.get('bundle') != 'GlassSwitchDockPrefs':
        raise ValueError('Wrong PreferenceLoader entry bundle')
    filt = plistlib.loads((ROOT / 'src/Filter.plist').read_bytes())
    if not filt.get('Filter', {}).get('Bundles'):
        raise ValueError('Injection filter must explicitly select bundles')
    for name in ('icon.png', 'icon@2x.png', 'icon@3x.png', 'pkgicon.png'):
        p = icon_source(name)
        if not p.is_file() or not p.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Missing approved PNG: ' + rel(p))
    return {'counts': counts, 'vendor': vendor_manifest(), 'preference_keys': sorted(KEYS),
            'sources': {k: [rel(p) for p in v] for k, v in sources.items() if isinstance(v, list)}}


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--output')
    args = parser.parse_args()
    result = check()
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        p = Path(args.output); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    print(text)
