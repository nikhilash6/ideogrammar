#!/usr/bin/env bash
#
# Start/stop helper for comfy_proxy.py (the same-origin proxy that lets the
# Ideogrammar editor reach ComfyUI from a browser without CORS).
#
# Usage:
#   ./comfy_proxy.sh start      # start in the background
#   ./comfy_proxy.sh stop       # stop it
#   ./comfy_proxy.sh restart
#   ./comfy_proxy.sh status
#   ./comfy_proxy.sh logs       # tail the log
#
# Override defaults via environment variables:
#   COMFY_URL=http://127.0.0.1:8188   # ComfyUI server
#   PROXY_HOST=0.0.0.0                    # 0.0.0.0 = reachable from the LAN
#   PROXY_PORT=8189                       # port the editor is served on
#   PYTHON=python3
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$DIR/comfy_proxy.pid"
LOGFILE="$DIR/comfy_proxy.log"

# Load local, untracked overrides (real ComfyUI IP, etc.) so they stay out of
# the tracked code. Pre-set environment variables still win.
ENV_FILE="${COMFY_PROXY_ENV:-$DIR/comfy_proxy.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

COMFY_URL="${COMFY_URL:-http://127.0.0.1:8188}"
PROXY_HOST="${PROXY_HOST:-0.0.0.0}"
PROXY_PORT="${PROXY_PORT:-8189}"
PYTHON="${PYTHON:-python3}"

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

lan_ip() {
  # best-effort LAN address for the "open this" hint
  if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  else
    echo "<this-host>"
  fi
}

start() {
  if is_running; then
    echo "Already running (pid $(cat "$PIDFILE")). Open: http://$(lan_ip):$PROXY_PORT/"
    return 0
  fi
  echo "Starting proxy: $PROXY_HOST:$PROXY_PORT -> $COMFY_URL"
  nohup "$PYTHON" "$DIR/comfy_proxy.py" \
    --host "$PROXY_HOST" --port "$PROXY_PORT" --comfy "$COMFY_URL" \
    >"$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"
  sleep 1
  if is_running; then
    echo "Started (pid $(cat "$PIDFILE"))."
    echo "Open the editor at: http://$(lan_ip):$PROXY_PORT/   (or http://localhost:$PROXY_PORT/ on this host)"
    echo "Logs: $LOGFILE"
  else
    echo "Failed to start. Last log lines:" >&2
    tail -n 20 "$LOGFILE" >&2 || true
    rm -f "$PIDFILE"
    exit 1
  fi
}

stop() {
  if ! is_running; then
    echo "Not running."
    rm -f "$PIDFILE"
    return 0
  fi
  local pid; pid="$(cat "$PIDFILE")"
  echo "Stopping (pid $pid)…"
  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    is_running || break
    sleep 0.3
  done
  if is_running; then
    echo "Force-killing…"
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
  echo "Stopped."
}

status() {
  if is_running; then
    echo "Running (pid $(cat "$PIDFILE")) on $PROXY_HOST:$PROXY_PORT -> $COMFY_URL"
    echo "Open: http://$(lan_ip):$PROXY_PORT/"
  else
    echo "Not running."
  fi
}

# ---- systemd service (background, survives logout/reboot) ------------------
# Default scope is the per-user systemd instance (no sudo). Set
# SERVICE_SCOPE=system to install a system-wide service (uses sudo).
SERVICE_NAME="comfy_proxy.service"
SERVICE_SCOPE="${SERVICE_SCOPE:-user}"

unit_text() {
  cat <<UNIT
[Unit]
Description=Ideogrammar ComfyUI proxy ($PROXY_HOST:$PROXY_PORT -> $COMFY_URL)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
ExecStart=$PYTHON $DIR/comfy_proxy.py --host $PROXY_HOST --port $PROXY_PORT --comfy $COMFY_URL
Restart=on-failure
RestartSec=3
$( [ -n "${SAM_CHECKPOINT:-}" ] && echo "Environment=SAM_CHECKPOINT=$SAM_CHECKPOINT" )
$( [ -n "${SAM_CHECKPOINT:-}" ] && echo "Environment=SAM_MODEL_TYPE=${SAM_MODEL_TYPE:-vit_b}" )
$( [ "$SERVICE_SCOPE" = system ] && echo "User=$(id -un)" )

[Install]
WantedBy=$( [ "$SERVICE_SCOPE" = system ] && echo multi-user.target || echo default.target )
UNIT
}

install_service() {
  # Free the port: stop any script-managed instance first.
  is_running && stop || true
  if [ "$SERVICE_SCOPE" = system ]; then
    echo "Installing system service (sudo)…"
    unit_text | sudo tee "/etc/systemd/system/$SERVICE_NAME" >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"
    echo "Installed. Manage with: sudo systemctl {status|restart|stop} $SERVICE_NAME"
    sudo systemctl --no-pager status "$SERVICE_NAME" | head -n 5 || true
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local unitdir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$unitdir"
    unit_text > "$unitdir/$SERVICE_NAME"
    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE_NAME"
    # Keep it running after logout / across reboots.
    loginctl enable-linger "$(id -un)" 2>/dev/null \
      && echo "Linger enabled (survives logout/reboot)." \
      || echo "Note: could not enable linger automatically — run: sudo loginctl enable-linger $(id -un)"
    echo "Installed. Manage with: systemctl --user {status|restart|stop} $SERVICE_NAME"
    systemctl --user --no-pager status "$SERVICE_NAME" | head -n 5 || true
  fi
  echo "Open the editor at: http://$(lan_ip):$PROXY_PORT/"
}

uninstall_service() {
  if [ "$SERVICE_SCOPE" = system ]; then
    sudo systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
    sudo systemctl daemon-reload
  else
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE_NAME"
    systemctl --user daemon-reload
  fi
  echo "Service removed."
}

case "${1:-}" in
  start)             start ;;
  stop)              stop ;;
  restart)           stop; start ;;
  status)            status ;;
  logs)              tail -f "$LOGFILE" ;;
  install-service)   install_service ;;
  uninstall-service) uninstall_service ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|install-service|uninstall-service}"
    echo "  install-service installs a background systemd service (user scope; SERVICE_SCOPE=system for system-wide)."
    exit 2
    ;;
esac
