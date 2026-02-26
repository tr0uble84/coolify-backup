#!/bin/bash
# =============================================================================
# Coolify Full Backup Script
# Backs up: Coolify DB, .env, SSH keys, and optionally all app Docker volumes
# Run on the server where Coolify is installed (Linux)
# =============================================================================

set -euo pipefail

# --- Configuration ---
BACKUP_ROOT="${BACKUP_ROOT:-/root/coolify-backups}"
COOLIFY_DATA="${COOLIFY_DATA:-/data/coolify}"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-0}"   # 0 = keep all; set e.g. 7 to keep last 7 days
BACKUP_VOLUMES="${BACKUP_VOLUMES:-true}"  # set false to skip app volume backups

# Coolify container names (adjust if you use different names)
COOLIFY_DB_CONTAINER="${COOLIFY_DB_CONTAINER:-coolify-db}"

# --- Helpers ---
log() { echo "[$(date +%H:%M:%S)] $*"; }
err() { echo "[$(date +%H:%M:%S)] [ERROR] $*" >&2; }
warn() { echo "[$(date +%H:%M:%S)] [WARN] $*" >&2; }

cleanup_old_backups() {
  if [ "$RETENTION_DAYS" -le 0 ]; then
    return 0
  fi
  log "Pruning backups older than $RETENTION_DAYS days..."
  find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" ! -path "$BACKUP_ROOT" -exec rm -rf {} + 2>/dev/null || true
}

# --- Pre-flight ---
if [ ! -d "$COOLIFY_DATA" ]; then
  err "Coolify data path not found: $COOLIFY_DATA. Set COOLIFY_DATA if different."
  exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -q "^${COOLIFY_DB_CONTAINER}$"; then
  err "Coolify DB container '$COOLIFY_DB_CONTAINER' not found. Is Coolify running?"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
log "Backup directory: $BACKUP_DIR"

# --- 1. Coolify PostgreSQL database ---
log "Backing up Coolify database (${COOLIFY_DB_CONTAINER})..."
docker exec "$COOLIFY_DB_CONTAINER" \
  pg_dump --format=custom --no-acl --no-owner -U coolify coolify \
  > "$BACKUP_DIR/coolify-db.dump" 2>/dev/null || {
  err "Database dump failed. Try: docker exec $COOLIFY_DB_CONTAINER pg_dump -U coolify coolify"
  exit 1
}
log "Database backup done: coolify-db.dump"

# --- 2. Coolify .env (contains APP_KEY - required for restore) ---
ENV_FILE="${COOLIFY_DATA}/source/.env"
if [ -f "$ENV_FILE" ]; then
  cp -a "$ENV_FILE" "$BACKUP_DIR/coolify.env"
  log "Backed up: coolify.env"
else
  warn ".env not found at $ENV_FILE; save APP_KEY manually for restore."
fi

# --- 3. SSH keys (required so Coolify can reach managed servers after restore) ---
SSH_KEYS_DIR="${COOLIFY_DATA}/ssh/keys"
if [ -d "$SSH_KEYS_DIR" ] && [ -n "$(ls -A "$SSH_KEYS_DIR" 2>/dev/null)" ]; then
  mkdir -p "$BACKUP_DIR/ssh/keys"
  cp -a "$SSH_KEYS_DIR"/* "$BACKUP_DIR/ssh/keys/"
  log "Backed up SSH keys from $SSH_KEYS_DIR"
else
  warn "No SSH keys found in $SSH_KEYS_DIR"
fi

# --- 4. Optional: all Docker volumes (application data) ---
if [ "$BACKUP_VOLUMES" = "true" ]; then
  VOLUMES_BACKUP_DIR="$BACKUP_DIR/volumes"
  mkdir -p "$VOLUMES_BACKUP_DIR"
  VOLUME_LIST=$(docker volume ls -q)
  VOLUME_COUNT=0
  for VOL in $VOLUME_LIST; do
    # Skip empty
    [ -z "$VOL" ] && continue
    log "Backing up volume: $VOL"
    BACKUP_FILE="${VOLUMES_BACKUP_DIR}/${VOL}-backup.tar.gz"
    if docker run --rm \
      -v "$VOL":/volume:ro \
      -v "$VOLUMES_BACKUP_DIR":/backup \
      busybox \
      tar czf "/backup/${VOL}-backup.tar.gz" -C /volume . 2>/dev/null; then
      VOLUME_COUNT=$((VOLUME_COUNT + 1))
    else
      warn "Failed to backup volume: $VOL"
    fi
  done
  log "Volume backups completed: $VOLUME_COUNT volumes in $VOLUMES_BACKUP_DIR"
else
  log "Skipping Docker volume backups (BACKUP_VOLUMES=false)"
fi

# --- 5. Create a manifest for restore reference ---
MANIFEST="$BACKUP_DIR/MANIFEST.txt"
{
  echo "Coolify Full Backup — $BACKUP_TIMESTAMP"
  echo "Created: $(date -Iseconds)"
  echo "---"
  echo "Contents:"
  echo "  - coolify-db.dump    (PostgreSQL custom format; restore with pg_restore)"
  echo "  - coolify.env        (APP_KEY and config; copy to /data/coolify/source/.env)"
  echo "  - ssh/keys/          (Coolify SSH keys; copy to /data/coolify/ssh/keys/)"
  if [ "$BACKUP_VOLUMES" = "true" ]; then
    echo "  - volumes/           (Docker volume tarballs; restore per volume with restore script)"
  fi
  echo ""
  echo "Restore Coolify instance: https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify"
  echo "Restore app volumes: https://coolify.io/docs/knowledge-base/how-to/migrate-apps-different-host"
} > "$MANIFEST"
log "Manifest written: $MANIFEST"

# --- 6. Optional: create a single tarball of this backup ---
ARCHIVE_NAME="coolify-full-backup-${BACKUP_TIMESTAMP}.tar.gz"
cd "$BACKUP_ROOT"
tar czf "$ARCHIVE_NAME" "$BACKUP_TIMESTAMP"
log "Archive created: $BACKUP_ROOT/$ARCHIVE_NAME"

# --- 7. Retention ---
cleanup_old_backups

log "Full backup completed: $BACKUP_DIR"
log "Archive: $BACKUP_ROOT/$ARCHIVE_NAME"
