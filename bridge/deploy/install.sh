#!/usr/bin/env bash
# Installs/updates the Linkup bridge service and its public path next to Navidrome on the Tailscale Funnel.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$HOME/.linkup/.venv/bin/python" ] || uv venv -q --python 3.12 "$HOME/.linkup/.venv"

REQ="$HERE/requirements.txt"
[ -f "$REQ" ] || REQ="$HERE/deploy/requirements.txt"
uv pip install -q --python "$HOME/.linkup/.venv/bin/python" -r "$REQ"

# Warn if any sessions are currently running before restart
RUNNING_COUNT=$("$HOME/.linkup/.venv/bin/python" -c "
import sys
try:
    from linkup_bridge.store import Store
    running = [s['id'] for s in Store().sessions() if s.get('status') == 'running']
    print(len(running))
except Exception:
    print(0)
" 2>/dev/null || echo 0)

if [ "$RUNNING_COUNT" -gt 0 ]; then
  echo "WARNING: $RUNNING_COUNT session(s) are currently running! Restarting will stop them."
fi

sudo install -m 644 "$HERE/deploy/linkup-bridge.service" /etc/systemd/system/linkup-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now linkup-bridge.service
sudo systemctl restart linkup-bridge.service

# `funnel` (not `serve`): a plain serve on 443 would switch the public Funnel off.
tailscale funnel --bg --https=443 --set-path /linkup http://127.0.0.1:8890/linkup >/dev/null

# Health-check the public URL at the end
PUBLIC_URL=$("$HOME/.linkup/.venv/bin/python" -c "
from linkup_bridge.__main__ import get_public_url
print(get_public_url())
" 2>/dev/null || echo "")

if [ -n "$PUBLIC_URL" ]; then
  HEALTH_URL="$PUBLIC_URL/linkup/health"
  echo "Checking health at $HEALTH_URL..."
  HEALTHY=0
  for i in {1..10}; do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      HEALTHY=1
      break
    fi
    sleep 1
  done
  if [ "$HEALTHY" -eq 1 ]; then
    echo "Health check passed: $HEALTH_URL is responding."
  else
    echo "WARNING: Health check did not respond for $HEALTH_URL after 10 attempts."
  fi
fi

echo "Linkup bridge running. Pair your phone:  cd $HERE && $HOME/.linkup/.venv/bin/python -m linkup_bridge pair"
