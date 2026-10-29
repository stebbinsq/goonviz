#!/usr/bin/env bash
# Publish the web app to https://goonviz.live
# GitHub Pages serves the gh-pages branch, which is just the web/ folder of main.
#   tools/deploy_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/build_web.py
if ! git diff --quiet -- web || [ -n "$(git ls-files --others --exclude-standard web)" ]; then
    echo "web/ has uncommitted changes (maybe from the rebuild). Commit them first, then run this again."
    exit 1
fi
git push origin main
git push --force origin "$(git subtree split --prefix web main)":refs/heads/gh-pages
echo "Deployed. goonviz.live updates within a minute or two."
