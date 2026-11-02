#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
BUILD_LOG_ROOT="$PWD/build/logs"
BUILD_DIAGNOSTICS="$PWD/scripts/build_diagnostics.py"
mkdir -p "$BUILD_LOG_ROOT"
run_logged_build() {
  local build_label="$1"
  shift
  local build_log="$BUILD_LOG_ROOT/$build_label-$(date +%Y%m%d-%H%M%S)-$$.log"
  local build_status
  set +e
  "$@" 2>&1 | tee "$build_log"
  build_status=${PIPESTATUS[0]}
  set -e
  if [ "$build_status" -ne 0 ]; then
    if command -v python3 >/dev/null; then
      python3 "$BUILD_DIAGNOSTICS" "$build_log" || true
    else
      echo "Build failed. Full log: $build_log"
    fi
  fi
  return "$build_status"
}
xcodegen generate
run_logged_build iOS xcodebuild -project ExtendDesk.xcodeproj -scheme ExtendDesk -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
(cd MacCompanion && xcodegen generate && run_logged_build Mac xcodebuild -project ExtendDeskLink.xcodeproj -scheme ExtendDeskLink -derivedDataPath ../build/Mac CODE_SIGNING_ALLOWED=NO build)
