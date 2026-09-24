#!/bin/sh
# Runs NowCore tests. With only the Command Line Tools installed (no Xcode),
# swift-testing needs its framework path and the broken Foundation cross-import disabled.
set -e
cd "$(dirname "$0")"
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if xcode-select -p | grep -q CommandLineTools; then
  exec swift test -Xswiftc -F$F -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xlinker -F$F -Xlinker -rpath -Xlinker $F "$@"
fi
exec swift test "$@"
