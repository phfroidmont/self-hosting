# Grafana backup and recovery

The `hel1` daily Borg job first creates an online SQLite backup of
`/nix/var/data/grafana/data/grafana.db`. Grafana stays running. The snapshot is
validated with SQLite `quick_check` and checks for the `user`, `dashboard`, and
`data_source` tables before atomic publication at
`/nix/var/data/backup/grafana.sqlite` (root-owned, mode `0600`).

Snapshot failure aborts the backup; an older snapshot is never used as a fallback.
SQLite lock waits are bounded and the snapshot command has a 60-second deadline.
Borg excludes the live database, its journal/WAL sidecars, and Grafana's log
directory. Other Grafana files remain covered. Borg warnings still fail the job.

The existing scheduled restore test extracts the snapshot and repeats its
integrity and schema checks alongside the existing application restore checks.
These checks validate SQLite recovery, not a full Grafana application startup.

## Recover Grafana

1. Select a known successful archive and extract
   `nix/var/data/backup/grafana.sqlite` into a private temporary directory. Use the
   repository and credential environment from `borgbackup-job-data.service`;
   do not print the passphrase. Run `PRAGMA quick_check;` and check the expected
   Grafana tables before using the file.
2. Restore the NixOS Grafana configuration and the original SOPS-managed
   `grafanaSecretKey` (`grafana/secret_key`). The database alone cannot recover
   credentials encrypted using this key. Restore any required plugins and other
   Grafana files from the archive as well.
3. Stop `grafana.service`. Preserve its current database and any `-wal`, `-shm`,
   and `-journal` sidecars together in a private rollback directory. Never combine
   old sidecars with the restored snapshot.
4. Install the validated snapshot at
   `/nix/var/data/grafana/data/grafana.db`, owned by the configured Grafana service
   user/group, mode `0600`. Check the effective service group rather than copying
   a historical on-disk group. Leave the database parent directory permissions
   intact.
5. Start `grafana.service`; check the journal and `/api/health`, then verify login,
   dashboards, data sources, alert rules, and encrypted credentials.

## Verify a backup change

Run the targeted flake check `checks.x86_64-linux.grafana-backup`, build/deploy
`hel1`, and run `borgbackup-job-data.service`. Its existing hooks briefly stop
Jellyfin and torrent services. Require exit status zero, an archive without the
`.failed` suffix, and a fresh `/nix/var/data/backup/backup-ok` timestamp.
Confirm archive contents include the snapshot and exclude live Grafana database
files/logs. Run `borgbackup-check-data.service` and
`borgbackup-restore-test-data.service`, then check application services and Monit.

## Verified rollout — 2026-09-29 (CEST)

- The regression check passed (concurrent WAL writes, missing/corrupt/locked
  sources, snapshot permissions, real Borg exclusions/extraction, and rejection
  of corrupt or empty-schema restored databases). ShellCheck and formatting
  checks passed.
- The system built on `hel1`, where the required FoundryVTT package was already
  available; local full-system/deploy checks were blocked by its manual-download
  dependency. Remote dry activation and deployment succeeded.
- Archive `hel1-data-2026-09-29T03:05:42` completed successfully at 03:11:28.
  Its contents include `nix/var/data/backup/grafana.sqlite` and exclude the live
  Grafana database, sidecars, and log directory.
- The latest-archive Borg check passed at 03:12:20; the application restore test
  passed at 03:12:42. All three success markers advanced.
- Grafana remained running throughout. Jellyfin and all six torrent services
  were active afterwards; systemd reported no failed units and Monit's
  `failed-units` check returned `OK`.

The PostgreSQL collation-version warnings observed during this rollout were
subsequently resolved; see [PostgreSQL maintenance](postgresql-maintenance.md).
