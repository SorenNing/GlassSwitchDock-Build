"""Execute the shared routing policy without the simulator's temp-path branch."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class StatePath(unittest.TestCase):
    def test_production_namespace_selection_and_failures(self):
        compiler = shutil.which('clang') or shutil.which('cc')
        self.assertIsNotNone(compiler, 'A C compiler is required for production path policy tests')
        fixture = r'''
#include "NGDockStatePath.h"
#include <assert.h>
#include <string.h>
static unsigned calls;
static const char *physical(const char *p) {
    ++calls;
    assert(strcmp(p,NG_DOCK_LOGICAL_STATE_PATH)==0);
    return "/var/containers/Bundle/Application/.jbroot-fixture/var/mobile/Library/Preferences/com.ning.glassswitchdock.render";
}
static const char *failed(const char *p) { (void)p;return 0; }
static const char *relative(const char *p) { (void)p;return "relative/path"; }
static const char *empty(const char *p) { (void)p;return ""; }
int main(void) {
    assert(strcmp(NGDockStateCString(0,0),NG_DOCK_LOGICAL_STATE_PATH)==0);
    assert(strcmp(NGDockStateCString(0,physical),NG_DOCK_LOGICAL_STATE_PATH)==0 && calls==0);
    const char *front=NGDockStateCString(1,physical);
    const char *back=NGDockStateCString(1,physical);
    assert(calls==2 && strcmp(front,back)==0);
    assert(strstr(front,"/.jbroot-fixture/") && strcmp(front,NG_DOCK_LOGICAL_STATE_PATH)!=0);
    assert(NGDockStateCString(1,0)==0);
    assert(NGDockStateCString(1,failed)==0);
    assert(NGDockStateCString(1,relative)==0);
    assert(NGDockStateCString(1,empty)==0);
    return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix='ngdock-path-') as tmp:
            source=Path(tmp)/'fixture.c'; binary=Path(tmp)/'fixture'
            source.write_text(fixture)
            subprocess.run([compiler,'-std=c99','-Wall','-Wextra','-Werror','-I',str(ROOT/'src'),str(source),'-o',str(binary)],check=True,capture_output=True,text=True,timeout=45)
            subprocess.run([str(binary)],check=True,capture_output=True,text=True,timeout=10)

    def test_front_and_back_use_the_same_production_helper(self):
        for name in ('src/NGSystemBackdrop.mm','render/NGDockPaths.mm'):
            text=(ROOT/name).read_text()
            self.assertIn('return NGDockSharedStateDirectory();',text)
            self.assertNotIn('return @"/var/mobile/Library/Preferences/com.ning.glassswitchdock.render";',text)
        helper=(ROOT/'src/NGDockStatePath.h').read_text()
        self.assertIn('#elif defined(NG_ROOTHIDE)',helper)
        self.assertIn('NGDockStateCString(1, jbroot)',helper)
