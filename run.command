#!/bin/sh
set -eu
cd "$(dirname "$0")"
if command -v love >/dev/null 2>&1; then
    exec love . "$@"
fi
for runtime in .runtime/love.app /Applications/love.app /Applications/LOVE.app; do
    if [ -x "$runtime/Contents/MacOS/love" ]; then
        exec "$runtime/Contents/MacOS/love" . "$@"
    fi
done
printf '%s\n' 'LÖVE 11.5 is required. Download it from https://love2d.org, then run love .'
exit 1
