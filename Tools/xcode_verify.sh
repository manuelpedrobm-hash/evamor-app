#!/bin/zsh
set -euo pipefail

developer="/Applications/Xcode.app/Contents/Developer"
if [[ ! -x "$developer/usr/bin/xcodebuild" ]]; then
    echo "No se encontró Xcode en /Applications/Xcode.app" >&2
    exit 1
fi

export DEVELOPER_DIR="$developer"
export PATH="$developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"

root="${0:A:h:h}"
derived="${TMPDIR:-/tmp}/MeditacionDerivedData"

xcodebuild \
    -project "$root/Meditacion.xcodeproj" \
    -scheme Meditacion \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ "${1:-}" == "--test" ]]; then
    device_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
    if [[ -z "$device_id" ]]; then
        echo "La compilación pasó, pero no hay un simulador iPhone disponible para XCTest." >&2
        exit 2
    fi
    xcodebuild test \
        -project "$root/Meditacion.xcodeproj" \
        -scheme Meditacion \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$device_id" \
        -derivedDataPath "$derived" \
        CODE_SIGNING_ALLOWED=NO
fi
