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
#   COMFY_URL=http://192.168.2.33:8188   # ComfyUI server
#   PROXY_HOST=0.0.0.0                    # 0.0.0.0 = reachable from the LAN
#   PROXY_PORT=8189                       # port the editor is served on
#   PYTHON=python3
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$DIR/comfy_proxy.pid"
LOGFILE="$DIR/comfy_proxy.log"

COMFY_URL="${COMFY_URL:-http://192.168.2.33:8188}"
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

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  logs)    tail -f "$LOGFILE" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 2
    ;;
esac
