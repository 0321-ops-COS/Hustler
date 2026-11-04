#!/bin/bash
# One-step fix for a missing file that is in the repo but not in the
# gitignored, XcodeGen-generated Hustler.xcodeproj.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
cd "$script_dir"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen is not installed, so the Xcode project cannot be regenerated. Install it with 'brew install xcodegen' and run this script again."
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is not installed, or xcode-select is not pointed at Xcode. Install Xcode, run 'sudo xcode-select -s /Applications/Xcode.app', and run this script again."
[ -f project.yml ] || fail "project.yml was not found. Run this script from a Hustler checkout (ios-app/regen-and-build.sh)."

printf 'Removing the old generated Hustler.xcodeproj...\n'
rm -rf Hustler.xcodeproj

printf 'Regenerating Hustler.xcodeproj from project.yml...\n'
xcodegen generate --spec project.yml || fail "XcodeGen could not generate Hustler.xcodeproj. Fix the error above and run this script again."

mkdir -p .build
log=.build/regen-and-build.log
printf 'Building the Hustler scheme for the iOS Simulator (log: ios-app/%s)...\n' "$log"
if xcodebuild build \
    -project Hustler.xcodeproj \
    -scheme Hustler \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO >"$log" 2>&1; then
    printf 'PASS: Hustler.xcodeproj was regenerated and the Hustler scheme built for the iOS Simulator.\n'
else
    printf 'FAIL: the Hustler scheme did not build. Last 40 lines of ios-app/%s:\n' "$log" >&2
    tail -n 40 "$log" >&2
    exit 1
fi
