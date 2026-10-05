#!/usr/bin/env bash
# Installs/updates the Linkup bridge service and its public path next to Navidrome on the Tailscale Funnel.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$HOME/.linkup/.venv/bin/python" ] || uv venv -q --python 3.12 "$HOME/.linkup/.venv"
uv pip install -q --python "$HOME/.linkup/.venv/bin/python" aiohttp qrcode
sudo install -m 644 "$HERE/deploy/linkup-bridge.service" /etc/systemd/system/linkup-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now linkup-bridge.service
sudo systemctl restart linkup-bridge.service
# `funnel` (not `serve`): a plain serve on 443 would switch the public Funnel off.
tailscale funnel --bg --https=443 --set-path /linkup http://127.0.0.1:8890/linkup >/dev/null
echo "Linkup bridge running. Pair your phone:  cd $HERE && $HOME/.linkup/.venv/bin/python -m linkup_bridge pair"
