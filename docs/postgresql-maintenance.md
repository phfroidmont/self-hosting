# PostgreSQL collation maintenance

`hel1` runs PostgreSQL 15. A libc or ICU upgrade can change text ordering while
existing indexes retain the old ordering. Refreshing a recorded collation version
alone does not repair those indexes.

## Inspect after locale-library upgrades

Run as the PostgreSQL administrator:

```sql
SELECT datname, datallowconn, datcollate, datcollversion AS recorded_version,
       pg_database_collation_actual_version(oid) AS actual_version
FROM pg_database
ORDER BY datname;
```

In each connectable database, also check named collations and index validity:

```sql
SELECT n.nspname, c.collname, c.collversion AS recorded_version,
       pg_collation_actual_version(c.oid) AS actual_version
FROM pg_collation c
JOIN pg_namespace n ON n.oid = c.collnamespace
WHERE c.collversion IS NOT NULL
  AND c.collversion IS DISTINCT FROM pg_collation_actual_version(c.oid);

SELECT indexrelid::regclass, indisvalid, indisready
FROM pg_index
WHERE NOT indisvalid OR NOT indisready;
```

`C`/`POSIX` collations have no library version to refresh. The pristine,
non-connectable `template0` also has a null recorded database collation version;
do not enable connections or alter it merely to make a version comparison match.

## Repair procedure

1. Inventory affected indexes, named-collation dependencies, partitioning,
   generated columns, materialized views, and constraints. Index rebuilding alone
   is not sufficient for every possible collation-dependent object. Inspect
   system-catalog index collations separately: `REINDEX DATABASE` excludes system
   catalogs.
2. Take fresh custom-format database dumps and a globals dump in a root-only
   directory. Verify dump listings, read/decompress the complete archives with
   `pg_restore --file=/dev/null`, and record checksums. Do not print globals dumps,
   which include role credentials.
3. Pause affected applications, record which services were running, and check
   that their database clients have disconnected. Use bounded lock and statement
   timeouts. Run each database's maintenance sequentially with
   `psql -X -v ON_ERROR_STOP=1`.
4. Rebuild indexes before refreshing the database version. For example, while
   connected to `forgejo`, run these as separate commands outside a transaction:

   ```sql
   REINDEX DATABASE forgejo;
   -- Require zero invalid/unready indexes before continuing.
   ALTER DATABASE forgejo REFRESH COLLATION VERSION;
   ANALYZE;
   ```

   A rebuild failure must stop the repair before the refresh. Resolve the actual
   failure rather than suppressing the warning. Ordinary reindexing requires a
   maintenance window; it also supports rebuilding Immich's VectorChord indexes
   without relying on concurrent-reindex support.

5. Refresh stale named collation definitions only after rebuilding their
   dependent objects, or verifying that they have no dependencies. Check
   `pg_depend` with `refclassid = 'pg_collation'::regclass` and the collation's OID.
   Save the previous metadata before updating it. Include `template1` in the
   inspection so newly created databases inherit current metadata.
6. Resume previously running services, verify application/database health and
   fresh warning-free connections, and run the regular backup and restore checks.

Do not put unconditional collation-version refreshes into the NixOS PostgreSQL
startup/setup service: they would hide future mismatches without rebuilding data.

## Completed maintenance — 2026-09-29 (CEST)

The default libc collation version was `2.40` in `forgejo`, `immich`, `roundcube`,
`postgres`, and `template1`; the installed libc supplied `2.42`.

- Retired experimental databases `dolibarr` (`2.39`), `odoo` (`2.39`), and
  `mastodon` (`2.37`) were removed at the owner's request after recovery dumps
  were verified. No active clients were present; no forced disconnections were
  used for their removal.
- Recovery files are on `hel1` in
  `/nix/var/data/backup/postgresql-collation-20260929/`, owned by root, directory
  mode `0700`, file mode `0600`. This includes eight pre-maintenance database
  dumps, `globals.sql`, `SHA256SUMS`, and before/after named-collation audit logs.
  The directory is included in the regular Borg backup. Archive readability and
  checksums were verified; a full restore of the retired applications was not
  performed.
- Forgejo, Immich's backend, and Roundcube's PHP pool were paused from
  **03:27:00 to 03:27:37**. Each of the five remaining mismatched databases was
  reindexed, checked for valid indexes, refreshed to `2.42`, and analyzed.
- The affected databases had no partitioned tables, generated columns, or
  materialized views. Immich's check constraints did not depend on text ordering.
  System-catalog indexes used the unaffected `C` collation. Immich's two
  VectorChord indexes were rebuilt successfully alongside its other indexes.
- Stale named libc/ICU collation definitions had no tracked dependent objects.
  Their versions were refreshed in all seven connectable databases, with a
  dependency guard immediately before each update. Nextcloud's default database
  version already matched; Synapse uses `C`. `template0` stayed pristine.
- All seven connectable databases subsequently reported zero invalid/unready
  indexes and zero named-collation version mismatches. All versioned database
  defaults matched `2.42`, and fresh connections produced no collation warnings.
- Forgejo's health endpoint passed both cache and database checks, Immich's ping
  endpoint returned `pong`, and Roundcube returned HTTP 200. All resumed services
  were active and systemd reported no failed units.
- Follow-up archive `hel1-data-2026-09-29T03:28:09` completed at **03:33:18**,
  with no PostgreSQL collation warnings. The latest-archive Borg check passed at
  **03:34:27**, and the regular application restore test passed at **03:34:49**.
  The maintenance recovery directory was then extracted from that off-site
  archive: all eight dumps and the globals file matched their recorded checksums,
  and every extracted database dump was fully read/decompressed by `pg_restore`.
  Monit's `failed-units` check reported `OK`.
