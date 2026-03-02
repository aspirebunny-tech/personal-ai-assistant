#!/bin/zsh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PAI_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SERVER_DIR="${PAI_SERVER_DIR:-$PROJECT_ROOT/server}"
NODE_BIN="$(command -v node || true)"
TAILSCALE_BIN="$(command -v tailscale || true)"

LOG_OUT="/tmp/pai_watchdog.log"
LOG_ERR="/tmp/pai_watchdog.err"
SERVER_LOG="/tmp/pai_server.log"
SERVER_ERR="/tmp/pai_server.err"
PID_FILE="/tmp/pai_server.pid"
HEALTH_URL="http://127.0.0.1:3000/api/health"

mkdir -p /tmp
touch "$LOG_OUT" "$LOG_ERR" "$SERVER_LOG" "$SERVER_ERR"

log() {
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_OUT"
}

server_healthy() {
  curl -fsS --max-time 4 "$HEALTH_URL" >/dev/null 2>&1
}

port_busy() {
  lsof -iTCP:3000 -sTCP:LISTEN -n -P >/dev/null 2>&1
}

start_server() {
  if [[ -z "$NODE_BIN" ]]; then
    log "ERROR: node binary not found"
    return 1
  fi
  (
    cd "$SERVER_DIR" || exit 1
    nohup "$NODE_BIN" src/index.js >> "$SERVER_LOG" 2>> "$SERVER_ERR" &
    echo $! > "$PID_FILE"
  )
  sleep 2
  if server_healthy; then
    log "Server started successfully"
  else
    log "WARN: server start attempted but health not ready yet"
  fi
}

ensure_tailscale() {
  if [[ -z "$TAILSCALE_BIN" ]]; then
    log "WARN: tailscale binary not found"
    return 0
  fi

  # Non-blocking: avoid calling `tailscale status` here because on some systems
  # it can hang and keep launchd job alive.
  if pgrep -x "Tailscale" >/dev/null 2>&1; then
    log "Tailscale app running"
  else
    log "WARN: Tailscale app not running, opening it"
    open -ga Tailscale >/dev/null 2>&1 || true
  fi
}

ensure_server() {
  if server_healthy; then
    log "Server healthy"
    return 0
  fi

  if port_busy; then
    log "Port 3000 busy but health failed; trying graceful restart"
    pkill -f "node .*server/src/index.js" >/dev/null 2>&1 || true
    sleep 1
  fi

  start_server
}

main() {
  ensure_tailscale
  ensure_server
}

main >> "$LOG_OUT" 2>> "$LOG_ERR"
