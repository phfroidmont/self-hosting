# STB WordPress archive

The STB WordPress site was retired on 2026-10-02 and replaced by the static
page in `sites/stb`. Its data is kept until it is certainly no longer needed.

| Item | Value |
| --- | --- |
| Archive directory | `/nix/var/data/stb-archive` (`0700`, root) |
| Database dump | `stb_mariadb.sql` (MariaDB 11.4.13, database `stb`) |
| WordPress files | `wordpress/` (WordPress 7.1, PHP 8.3, `sport` theme) |
| Last running commit | `19be3f8` |

The archive lives under `/nix/var/data`, so every Borg run keeps a copy. The
weekly restore test extracts the dump and `wp-config.php` and alerts through
monit if either is missing or empty. Removing the archive therefore requires
removing those paths from `restoreTestPaths` in `profiles/hel.nix`.

## Archiving procedure

Run before deploying the static site, while the containers still run:

```console
systemctl start stb-mariadb-dump.service
systemctl show --property=Result --value stb-mariadb-dump.service
install -d -m 0700 /nix/var/data/stb-archive
mv /nix/var/data/backup/stb_mariadb.sql /nix/var/data/stb-archive/
```

The result must be `success`. Deploy, then move the WordPress files once the
containers are stopped:

```console
mv /nix/var/data/stb-wordpress /nix/var/data/stb-archive/wordpress
```

Run a Borg backup and the restore test, and check that both results are
`success`:

```console
systemctl start borgbackup-job-data.service
systemctl start borgbackup-restore-test-data.service
systemctl show --property=Result --value \
  borgbackup-job-data.service borgbackup-restore-test-data.service
```

The MariaDB data files in `/var/lib/stb` are not needed once the dump is
verified; the logical dump is the source of truth.

## Restoring

Check out commit `19be3f8`; it contains the full rootless WordPress/MariaDB
module and `docs/stb-operations.md`, which describes the database import and
file ownership mapping. Restore into a loopback-only staging environment
rather than the public domain.
