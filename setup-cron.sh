#!/bin/bash
# =============================================================================
# Install or remove automated Coolify backups via cron
# Run on the Coolify server (Linux) as root or with sudo
# =============================================================================

set -euo pipefail

SCRIPT_PATH="${SCRIPT_PATH:-/root/coolify-full-backup.sh}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/coolify-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
# Full backup including volumes (set false to skip volumes)
BACKUP_VOLUMES="${BACKUP_VOLUMES:-true}"

CRON_ENV="BACKUP_ROOT=$BACKUP_ROOT RETENTION_DAYS=$RETENTION_DAYS BACKUP_VOLUMES=$BACKUP_VOLUMES"
CRON_LINE="0 2 * * * $CRON_ENV $SCRIPT_PATH"

usage() {
  echo "Usage: $0 {install|remove|status}"
  echo ""
  echo "  install  - Add cron job (daily 2 AM, ${RETENTION_DAYS}-day retention, volumes=${BACKUP_VOLUMES})"
  echo "  remove   - Remove the Coolify backup cron job"
  echo "  status   - Show current cron and script path"
  echo ""
  echo "Override defaults with env vars: SCRIPT_PATH, BACKUP_ROOT, RETENTION_DAYS, BACKUP_VOLUMES"
  exit 1
}

install_cron() {
  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "[ERROR] Backup script not found: $SCRIPT_PATH"
    echo "Copy coolify-full-backup.sh to $SCRIPT_PATH and chmod +x it first."
    exit 1
  fi
  if [ ! -x "$SCRIPT_PATH" ]; then
    echo "[ERROR] Script is not executable: $SCRIPT_PATH"
    exit 1
  fi
  ( crontab -l 2>/dev/null | grep -v "coolify-full-backup.sh" || true
    echo "# Coolify full backup (daily 2 AM, retention ${RETENTION_DAYS}d)"
    echo "$CRON_LINE"
  ) | crontab -
  echo "[OK] Cron installed: daily at 2:00 AM"
  echo "     $CRON_LINE"
}

remove_cron() {
  if crontab -l 2>/dev/null | grep -q "coolify-full-backup.sh"; then
    crontab -l 2>/dev/null | grep -v "coolify-full-backup.sh" | crontab -
    echo "[OK] Coolify backup cron job removed."
  else
    echo "[INFO] No Coolify backup cron job found."
  fi
}

status_cron() {
  echo "Script path:  $SCRIPT_PATH"
  echo "Backup root:  $BACKUP_ROOT"
  echo "Retention:    $RETENTION_DAYS days"
  echo "Backup vols:  $BACKUP_VOLUMES"
  echo ""
  echo "Current crontab (backup-related):"
  crontab -l 2>/dev/null | grep -E "coolify|$SCRIPT_PATH" || echo "  (none)"
}

case "${1:-}" in
  install) install_cron ;;
  remove)  remove_cron ;;
  status)  status_cron ;;
  *)       usage ;;
esac
