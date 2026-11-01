#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_libraries="$developer_dir/Library/Developer/usr/lib"
flags=(--disable-automatic-resolution --disable-xctest)

# Some Command Line Tools releases omit these paths from SwiftPM's test runner.
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
    flags+=(
        -Xswiftc -F -Xswiftc "$testing_frameworks"
        -Xlinker -F -Xlinker "$testing_frameworks"
        -Xlinker -rpath -Xlinker "$testing_frameworks"
        -Xlinker -rpath -Xlinker "$testing_libraries"
    )
fi

swift test "${flags[@]}" "$@"
