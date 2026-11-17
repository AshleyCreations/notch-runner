#!/bin/bash
# Standalone test run — no Xcode needed, just the Swift toolchain:
#   app/Tests/run.sh
# SessionRouter is deliberately free of AppKit and Settings so it can be
# exercised on its own, with the real timings shortened. Each suite is a
# directory because Swift only allows top-level code in a file named main.swift.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
status=0
for suite in */; do
  name="${suite%/}"
  echo "== $name"
  swiftc -o "$OUT/$name" \
    ../NotchRunner/EventServer.swift \
    ../NotchRunner/SessionRouter.swift \
    "$name/main.swift"
  "$OUT/$name" || status=1
done
exit $status
