#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project ExtendDesk.xcodeproj -scheme ExtendDesk -destination "${1:-platform=iOS Simulator,name=iPhone 16}" -derivedDataPath build/tests CODE_SIGNING_ALLOWED=NO test
