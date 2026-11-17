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
  # Each suite names the sources it needs in sources.txt. Written for the
  # bash 3.2 that ships with macOS, so no mapfile and no array expansion tricks.
  srcs=""
  while IFS= read -r line; do
    [ -n "$line" ] && srcs="$srcs ../NotchRunner/$line"
  done < "$name/sources.txt"
  swiftc -o "$OUT/$name" $srcs "$name/main.swift"
  "$OUT/$name" || status=1
done
exit $status
