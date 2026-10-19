#!/bin/bash
# coSHLink: double-click in Finder to open a Terminal window running
# coSHLink.sh --loop. Ctrl+C quits.

SCRIPT="$(cd "$(dirname "$0")" && pwd)/coSHLink.sh"

printf '\e]0;coSHLink\a\e[8;24;80t'   # title and 80x24 size of this window
sleep 0.5                             # let the window settle before drawing
exec "$SCRIPT" --loop
