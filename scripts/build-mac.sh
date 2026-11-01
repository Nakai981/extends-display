#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
xcodegen generate
xcodebuild -project ExtendDesk.xcodeproj -scheme ExtendDesk -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
(cd MacCompanion && xcodegen generate && xcodebuild -project ExtendDeskLink.xcodeproj -scheme ExtendDeskLink -derivedDataPath ../build/Mac CODE_SIGNING_ALLOWED=NO build)
