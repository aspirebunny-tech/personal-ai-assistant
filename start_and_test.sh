#!/bin/bash
set -euo pipefail

SERVER_DIR="$HOME/Desktop/personal-ai-assistant/server"
LOG="$SERVER_DIR/server.log"
PID="$SERVER_DIR/server.pid"

echo "=== Starting server ==="
cd "$SERVER_DIR"

# Start server (reuse if already running)
if [ -f "$PID" ] && ps -p "$(cat "$PID")" > /dev/null 2>&1; then
  echo "Server already running (PID $(cat "$PID"))"
else
  if [ -f "$PID" ]; then
    rm -f "$PID"
  fi
  npm start > "$LOG" 2>&1 &
  echo $! > "$PID"
  echo "Started server (PID $(cat "$PID"))"
fi

# Give it a moment
sleep 2

echo "--- Health check ---"
curl -s http://localhost:3000/api/health || true
echo

echo "--- Registration test ---"
curl -s -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secret","name":"Test User"}' \
  http://localhost:3000/api/auth/register || true
echo

echo "--- Logs (tail last 200) ---"
tail -n 200 "$LOG" || true
echo "=== Done ==="
