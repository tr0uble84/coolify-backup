# Coolify Full Backup Script

Bash script for a **full Coolify backup** on the server where Coolify runs (Linux). It backs up:

| What | Where in backup |
|------|------------------|
| Coolify PostgreSQL DB | `coolify-db.dump` |
| `.env` (APP_KEY, config) | `coolify.env` |
| SSH keys (for managed servers) | `ssh/keys/` |
| All Docker volumes (app data) | `volumes/<name>-backup.tar.gz` |

## Usage on your Coolify server

1. Copy `coolify-full-backup.sh` to the Coolify host (e.g. via SCP).
2. Make it executable and run:

```bash
chmod +x coolify-full-backup.sh
./coolify-full-backup.sh
```

## Options (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_ROOT` | `/root/coolify-backups` | Base directory for backups |
| `COOLIFY_DATA` | `/data/coolify` | Coolify data path |
| `BACKUP_VOLUMES` | `true` | Set `false` to skip Docker volume backups |
| `RETENTION_DAYS` | `0` | Delete backups older than N days (0 = keep all) |
| `COOLIFY_DB_CONTAINER` | `coolify-db` | DB container name |

**Examples:**

```bash
# Backup to a custom folder, skip volumes, keep 7 days
BACKUP_ROOT=/mnt/backups BACKUP_VOLUMES=false RETENTION_DAYS=7 ./coolify-full-backup.sh

# Backup only Coolify core (no app volumes)
BACKUP_VOLUMES=false ./coolify-full-backup.sh
```

## Output

- **Folder:** `$BACKUP_ROOT/YYYYMMDD_HHMMSS/` with dump, env, ssh keys, and optionally `volumes/`.
- **Archive:** `$BACKUP_ROOT/coolify-full-backup-YYYYMMDD_HHMMSS.tar.gz` (single file to copy off server).

## Restore

Restore in two parts: **Coolify instance** (DB, env, SSH keys) first, then **application volumes** if you backed them up.

---

### 1. Restore the Coolify instance (DB + config + SSH)

Do this on the **new** server where Coolify will run.

**A. Copy backup and get APP_KEY**

- Copy the backup folder (or `coolify-full-backup-YYYYMMDD_HHMMSS.tar.gz`) to the new server.
- If you still have the old server, get the key:
  ```bash
  cat /data/coolify/source/.env | grep APP_KEY
  ```
- Or use the backed-up file: your backup has `coolify.env` — open it and copy the `APP_KEY` value. **Keep it safe; you need it for decrypting data.**

**B. Install Coolify on the new server** (same major version as before)

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.0.0-beta.400
```

Replace `4.0.0-beta.400` with the version you were running.

**C. Stop Coolify**

```bash
docker stop coolify coolify-redis coolify-realtime coolify-proxy
```

**D. Restore the database**

Extract the backup if you have the tarball:

```bash
cd /root/coolify-backups
tar xzf coolify-full-backup-YYYYMMDD_HHMMSS.tar.gz
cd YYYYMMDD_HHMMSS
```

Then restore the dump (path to the dump file as you have it):

```bash
cat /root/coolify-backups/YYYYMMDD_HHMMSS/coolify-db.dump \
  | docker exec -i coolify-db \
  pg_restore --verbose --clean --no-acl --no-owner -U coolify -d coolify
```

Warnings about existing objects are often OK.

**E. Restore SSH keys**

```bash
rm -f /data/coolify/ssh/keys/*
cp /root/coolify-backups/YYYYMMDD_HHMMSS/ssh/keys/* /data/coolify/ssh/keys/
```

**F. Allow the old APP_KEY for decryption**

```bash
nano /data/coolify/source/.env
```

Add (use the APP_KEY from step A):

```
APP_PREVIOUS_KEYS=your_previous_app_key_here
```

Save and exit.

**G. Restart Coolify** (re-run the install command)

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s 4.0.0-beta.400
```

**H. Fix permissions if needed**

```bash
sudo chown -R root:root /data/coolify
```

Then open the Coolify dashboard and log in with your old credentials.

---

### 2. Restore application volumes (if you backed them up)

Your backup has `volumes/<volume-name>-backup.tar.gz` for each volume.

**For each app volume:**

1. In Coolify, deploy the app on the new server so the volume exists, then **stop** the app.
2. Find the volume name (Coolify UI or `docker volume ls`).
3. Restore that volume:

```bash
docker run --rm \
  -v VOLUME_NAME:/volume \
  -v /root/coolify-backups/YYYYMMDD_HHMMSS/volumes:/backup \
  busybox \
  sh -c "cd /volume && tar xzf /backup/VOLUME_NAME-backup.tar.gz"
```

Replace `VOLUME_NAME` and the backup path with your real volume name and path (e.g. `abc123_postgresql` and the correct date folder).

4. Start the app again in Coolify.

---

### Quick reference

| Step        | What to do |
|-------------|------------|
| APP_KEY     | From old server `/data/coolify/source/.env` or from backup `coolify.env` → set `APP_PREVIOUS_KEYS` on new server |
| DB          | `pg_restore` from `coolify-db.dump` into `coolify-db` |
| SSH keys    | Copy backup `ssh/keys/*` to `/data/coolify/ssh/keys/` |
| App volumes | Extract each `volumes/<name>-backup.tar.gz` into the matching volume with the `docker run ... busybox ... tar xzf` command above |

Official docs: [Backup and Restore Coolify](https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify), [Migrate applications (volumes)](https://coolify.io/docs/knowledge-base/how-to/migrate-apps-different-host).

## Cron (optional)

```bash
# Daily at 2 AM
0 2 * * * /root/coolify-full-backup.sh
```

Ensure `BACKUP_ROOT` is set in cron if needed, e.g.:

```bash
0 2 * * * BACKUP_ROOT=/root/coolify-backups /root/coolify-full-backup.sh
```
