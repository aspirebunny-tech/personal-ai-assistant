#!/bin/zsh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${PAI_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SERVER_DIR="${PAI_SERVER_DIR:-$PROJECT_ROOT/server}"
BACKUP_DIR="$SERVER_DIR/backups/nightly"
DATA_DIR="$SERVER_DIR/data"
UPLOADS_DIR="$SERVER_DIR/uploads"
TS="$(date '+%Y%m%d-%H%M%S')"
DEST="$BACKUP_DIR/$TS"
LOG_FILE="/tmp/pai_backup.log"

mkdir -p "$DEST" "$BACKUP_DIR"

{
  echo "$(date '+%Y-%m-%d %H:%M:%S') Starting backup -> $DEST"
  if [[ -d "$DATA_DIR" ]]; then
    cp -R "$DATA_DIR" "$DEST/data"
  fi
  if [[ -d "$UPLOADS_DIR" ]]; then
    cp -R "$UPLOADS_DIR" "$DEST/uploads"
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') Backup completed"
} >> "$LOG_FILE" 2>&1

# Keep last 14 nightly backups
ls -1dt "$BACKUP_DIR"/* 2>/dev/null | tail -n +15 | xargs -I{} rm -rf "{}"
