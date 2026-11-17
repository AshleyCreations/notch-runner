#!/bin/bash
# Copies the single sources of truth into the app's Resources folder.
# /game/index.html and /hooks/notch-runner-hook.sh are the originals; the copies
# here are build artefacts and are gitignored.
#
# Run before `xcodegen generate`: the project spec references these paths, and a
# folder reference cannot be created for a folder that does not exist yet.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p NotchRunner/Resources/game
cp ../game/index.html NotchRunner/Resources/game/index.html
cp ../hooks/notch-runner-hook.sh NotchRunner/Resources/notch-runner-hook.sh
chmod +x NotchRunner/Resources/notch-runner-hook.sh
