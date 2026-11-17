#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/setup .toolchain
exec > >(tee evidence/setup/setup.log) 2>&1
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'macOS + native Xcode required' >&2
  exit 1
fi
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-path
# Xcode 26 ships Metal as an on-demand component. Older Xcode includes it already.
if ! xcrun --sdk iphoneos metal --version; then
  xcodebuild -downloadComponent MetalToolchain
fi
xcrun --sdk iphoneos metal --version
xcrun --sdk iphoneos --find metallib
xcrun --sdk iphonesimulator --show-sdk-path
# Respect an existing original Theos SDK. Native compilation still uses the current
# Xcode SDK; this 16.5 SDK supplies Preferences' original private link interface.
if [[ -n "${THEOS:-}" && -f "$THEOS/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd" ]]; then
  printf '%s\n' 'Using supplied THEOS SDK 16.5 Preferences interface'
else
  python3 tools/fetch-sdk-interface.py
fi
python3 -m py_compile tools/*.py
