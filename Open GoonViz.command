#!/bin/bash
# Double-click to run GoonViz offline in Chrome (no internet needed).
cd "$(dirname "$0")"
open -a "Google Chrome" web/index.html 2>/dev/null || {
    osascript -e 'display alert "GoonViz needs Google Chrome" message "Install Chrome from google.com/chrome (Safari cannot talk to MIDI controllers), then double-click this again."'
}
