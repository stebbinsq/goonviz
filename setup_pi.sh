#!/usr/bin/env bash
# One-shot setup for Raspberry Pi 4 / 5 running Raspberry Pi OS Lite (64-bit).
#   ./setup_pi.sh            install dependencies
#   ./setup_pi.sh --service  ...and start Prism automatically on boot
# From a Mac, install_to_pi.sh runs this for you.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "== system packages"
sudo apt-get update
# Needed: Python, GPU drivers, audio I/O, and build tools in case a pip wheel has to compile.
sudo apt-get install -y python3-venv python3-dev python3-numpy build-essential pkg-config \
    libportaudio2 libasound2-dev libgl1 libegl1 libgles2 fonts-dejavu-core
# Nice to have: install one by one so a renamed package on a newer Pi OS can't block the rest.
for pkg in python3-opencv v4l-utils python3-picamera2 libjack-jackd2-dev; do
    sudo apt-get install -y "$pkg" || echo "   (skipped $pkg: not available on this Pi OS)"
done

echo "== python venv (sees apt's opencv/picamera2/numpy)"
python3 -m venv --system-site-packages .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt
if ! .venv/bin/python -c "import cv2" 2>/dev/null; then
    echo "   apt opencv missing; installing opencv from pip instead"
    .venv/bin/pip install opencv-python-headless
fi

echo "== permissions for GPU, audio, MIDI and camera"
sudo usermod -aG video,render,audio,input "$USER"

if [[ "${1:-}" == "--service" ]]; then
    echo "== installing systemd service"
    sed -e "s|__USER__|$USER|g" -e "s|__DIR__|$DIR|g" prism.service | sudo tee /etc/systemd/system/prism.service >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable prism.service
    echo "Prism will start on boot. Now: sudo systemctl start prism   (logs: journalctl -u prism -f)"
    if systemctl get-default | grep -q graphical; then
        echo "Note: this Pi boots to a desktop, which holds the display. Use Pi OS Lite, or:"
        echo "      sudo raspi-config -> System -> Boot -> Console Autologin"
    fi
fi

echo
echo "Done. Log out and back in (for group changes), then try:"
echo "  .venv/bin/python run.py --list-audio"
echo "  .venv/bin/python run.py --midi-monitor"
echo "  .venv/bin/python run.py --fake-audio"
