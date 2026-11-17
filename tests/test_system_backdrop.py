import json
import re
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

def source(name):return (ROOT/name).read_text()

class SystemBackdrop(unittest.TestCase):
    def test_no_foreign_runtime_or_background_capture(self):
        runtime='\n'.join(source(str(p.relative_to(ROOT))) for p in (ROOT/'render').glob('*') if p.suffix in {'.mm','.h','.metal'})
        self.assertNotRegex(runtime,r'com\.wkk\.systembox|HangLiquidDock|DockGlass\.metallib|SystemBoxLiquidGlassDockBackboardd\.dylib')
        dock=source('src/NGDock.mm')
        self.assertNotRegex(dock,r'NGWallpaperBackdrop|NSTimer|CADisplayLink|UIGraphics|renderInContext')
        self.assertFalse((ROOT/'src/NGWallpaperBackdrop.m').exists())
        self.assertFalse((ROOT/'src/NGWallpaperBackdrop.h').exists())
        self.assertIn('NGDockBackground',dock)
    def test_constructor_and_hooks_cannot_reinstall(self):
        text=source('render/NGDockRegister.mm')
        self.assertIn('if (Registered || Attempted) return;',text)
        self.assertLess(text.index('Attempted=true;'),text.index('hook((void *)NGRenderStripCode(render)'))
        self.assertIn('guard(RouteLock())',text)
        self.assertRegex(text,r'#ifndef NG_TESTING\s+__attribute__\(\(constructor\)\)')
        self.assertIn('if (Major<15 || Major>18)',text)
    def test_gpu_frame_has_exclusive_lease_until_completion(self):
        text=source('render/NGDockGPU.mm')
        self.assertIn('AcquireFrame(source.device)',text)
        self.assertIn('static auto *frames=new FrameTextures[24]',text)
        self.assertIn('frames[n].busy=true',text)
        self.assertIn('addCompletedHandler',text)
        self.assertIn('ReleaseFrame(frame)',text)
        self.assertIn('CurrentFrame->textures[name]',text)
        self.assertNotIn('waitUntilCompleted',text)
    def test_packet_publication_commits_only_after_success(self):
        text=source('src/NGSystemBackdrop.mm')
        self.assertLess(text.index('if (![packet writeToFile:file atomically:YES]) return NO;'),text.index('_lastPacket=published;'))
        self.assertLess(text.index('if (![accepted isEqualToString:_token]) return;'),text.index('self.layer.filters=@[filter]'))
        self.assertIn('self.layer.hidden=_surfaceHidden',text)
    def test_receipt_rejects_obsolete_token_pid_and_frame(self):
        back=source('render/NGDockRegister.mm');front=source('src/NGSystemBackdrop.mm')
        self.assertIn('frame<AcceptedFrame[slot]',back)
        self.assertIn('Packets[slot][@"token"]',back)
        self.assertIn('[ack[@"pid"] intValue]==_backendPID',front)
        self.assertIn('[ack[@"boot"] longLongValue]==NGBoot()',front)
    def test_transport_has_no_optical_material(self):
        text=source('render/NGDockTransport.metal')
        self.assertIn('source.sample(s,v.uv)',text)
        self.assertNotRegex(text,r'(?i)fresnel|refract|tint|bezel')
        build=source('tools/build.py')
        self.assertIn("def backend(self):",build)
        self.assertIn("self.src['render'] + self.src['cpp']",build)
        self.assertIn("ROOT/'render/Filter.plist'",build)
        self.assertIn("self.package(core, self.preferences(), self.backend())",build)
