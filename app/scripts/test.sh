#!/bin/bash
# Runs the test suite. Command Line Tools don't put the swift-testing macro plugin on the
# compiler's default search path, so pass it explicitly (otherwise builds fail intermittently).
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
