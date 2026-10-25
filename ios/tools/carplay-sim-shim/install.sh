#!/bin/zsh
# Builds the simulator CarPlay shim and loads it into the booted simulator's CarPlay host.
# Re-run after every simulator reboot. Undo: xcrun simctl spawn booted launchctl unsetenv DYLD_INSERT_LIBRARIES
set -e
cd "$(dirname "$0")"
OUT="$HOME/Library/Developer/forx-cp-shim.dylib"
xcrun -sdk iphonesimulator clang -arch arm64 -dynamiclib -mios-simulator-version-min=16.0 \
  -framework Foundation -o "$OUT" shim.m
xcrun simctl spawn booted launchctl setenv DYLD_INSERT_LIBRARIES "$OUT"
pkill -f CarPlayTemplateUIHost || true
echo "CarPlay simulator shim loaded ($OUT)"
