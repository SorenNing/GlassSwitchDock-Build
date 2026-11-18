"""Verify generated compatibility inputs and fail closed on upstream drift."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theseus_compat', ROOT/'tools/theseus_compat.py')
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class Compatibility(unittest.TestCase):
    def test_pinned_inputs_generate_without_changing_originals(self):
        paths = [next((ROOT/'Vendor/Theseus/Sources').rglob(name))
                 for name in ('TheseusSwitch.swift', 'TheseusRenderer.swift')]
        before = [p.read_bytes() for p in paths]
        with tempfile.TemporaryDirectory() as directory:
            outputs = compat.prepare_sources(paths, directory)
            self.assertEqual(len(outputs), 2)
            switch = outputs[0].read_text()
            self.assertIn('self.presentationGeneration == generation', switch)
            self.assertIn('private var theseusSourceView: UIView? { self }', switch)
            self.assertIn('self?.contentView.backgroundColor = .secondarySystemGroupedBackground', switch)
            self.assertIn('self?.thumbLayer.isHidden = true', switch)
            self.assertIn('private var theseusContainer: UIView? { superview?.superview }', switch)
            self.assertIn('guard completed.status == .completed', outputs[1].read_text())
        self.assertEqual(before, [p.read_bytes() for p in paths])

    def test_changed_or_duplicated_patch_anchor_is_rejected(self):
        path = next((ROOT/'Vendor/Theseus/Sources').rglob('TheseusSwitch.swift'))
        source = path.read_text()
        anchor = '    private var glassRevealed = false'
        for changed in (source.replace(anchor, ''), source.replace(anchor, anchor+'\n'+anchor)):
            with self.subTest(changed=changed[:30]):
                with self.assertRaises(ValueError):
                    compat.switch_source(changed)

    def test_production_and_harness_use_generated_sources(self):
        build = (ROOT/'tools/build.py').read_text()
        library = build.split('    def swift_library(self):', 1)[1].split('    def compile(', 1)[0]
        self.assertIn("prepare_sources(self.src['swift'], self.obj / 'compat')", library)
        self.assertLess(library.index('prepare_sources('), library.index('if self.harness:'))


if __name__ == '__main__':
    unittest.main()
