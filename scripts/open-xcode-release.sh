#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Run this script on your Mac. Xcode is required."
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Install and open Xcode first, then select it in Xcode > Settings > Locations > Command Line Tools."
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Install XcodeGen first: brew install xcodegen"
  exit 1
fi

xcodegen generate
open -a Xcode "$PWD/ExtendDesk.xcodeproj"
printf '\nXcode opened. The ExtendDesk Run action uses Release with the debugger disabled.\n'
printf 'Select ExtendDesk and your connected iPhone/iPad, then press Command-R.\n'
printf 'First run: select your Team in Signing & Capabilities and enable automatic signing.\n'
