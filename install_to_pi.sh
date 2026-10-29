#!/usr/bin/env bash
# Run this on your Mac once the Pi has booted. It copies Prism over, installs
# everything, sets it to start on boot, reboots the Pi, and checks your gear.
#
#   ./install_to_pi.sh yourname@prism.local
#
# Safe to re-run (e.g. after editing presets): files you changed on the Pi,
# like MIDI maps saved by MIDI learn, are newer there and won't be overwritten.
set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" || "$TARGET" != *@* ]]; then
    echo "usage: $0 username@prism.local   (the username you set in Raspberry Pi Imager)"
    exit 1
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH=(ssh -o ConnectTimeout=5 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new "$TARGET")

wait_for_pi() {
    printf "== waiting for %s " "$TARGET"
    until "${SSH[@]}" -o BatchMode=yes true 2>/dev/null; do printf "."; sleep 5; done
    echo " connected"
}

wait_for_pi

echo "== copying Prism"
rsync -az --update \
    --exclude .venv --exclude preview --exclude __pycache__ --exclude .claude \
    --exclude snapshots.json --exclude '*.pyc' \
    "$DIR/" "$TARGET:prism/"

echo "== installing (takes 5-15 minutes the first time)"
"${SSH[@]}" "cd ~/prism && bash setup_pi.sh --service"

echo "== rebooting the Pi"
"${SSH[@]}" "sudo reboot" || true
sleep 20
wait_for_pi
sleep 10

echo
echo "== checking your gear"
"${SSH[@]}" 'bash -s' <<'EOF'
cd ~/prism
echo "-- Prism service: $(systemctl is-active prism)"
echo "-- MIDI ports:"
.venv/bin/python -c "import mido; print('\n'.join('   ' + n for n in mido.get_input_names()) or '   none (is the MPD32 plugged in?)')"
echo "-- cameras:"
v4l2-ctl --list-devices 2>/dev/null | sed 's/^/   /' || echo "   none"
echo "-- audio inputs:"
.venv/bin/python run.py --list-audio | sed 's/^/ /'
echo "-- recent Prism log:"
journalctl -u prism -n 15 --no-pager | sed 's/^/   /'
EOF

echo
echo "Done. Prism should be on the projector. It starts by itself on every boot."
echo "Logs:  ssh $TARGET journalctl -u prism -f"
