# STB WordPress operations

The STB site runs WordPress 7.1 on PHP 8.3 with MariaDB 11.4.13. Both
containers run rootless as the `stb` system user and use digest-pinned images.

## Architecture

| Item | Value |
| --- | --- |
| Public URL | `https://www.societe-de-tir-bertrix.com` |
| WordPress backend | `127.0.0.1:8180` |
| WordPress files | `/nix/var/data/stb-wordpress` |
| MariaDB files | `/var/lib/stb/mariadb` |
| Database dump | `/nix/var/data/backup/stb_mariadb.sql` |
| Rootless user | `stb` (`5001:5001`) |
| Rootless network | `stb` |
| Maintenance marker | `/var/lib/stb-maintenance` |

MariaDB has no host port. WordPress is reachable only through the loopback
publication and nginx. `/xmlrpc.php` is blocked by nginx with a `404` response.

The database credentials are stored under `stb/` in `secrets.enc.yml`. The
application password is copied into the rootless runtime directory by
`prepare-stb-wordpress-secret.service` so PHP can read it without exposing the
original SOPS file to other host users.

## Routine checks

Check the services and public endpoints:

```console
systemctl status podman-stb-mariadb.service podman-stb-wordpress.service nginx.service
curl --fail-with-body --head https://www.societe-de-tir-bertrix.com/
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  https://www.societe-de-tir-bertrix.com/xmlrpc.php
```

The XML-RPC command must print `404`.

Inspect the rootless containers:

```console
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb \
      XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman ps
```

Confirm the effective versions:

```console
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman exec stb-wordpress php -r \
    'require "/var/www/html/wp-includes/version.php"; echo "$wp_version\n";'
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman exec stb-wordpress php --version
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman exec stb-mariadb mariadb --version
```

## Maintenance mode

Create the persistent nginx marker before any database, credential, or
application maintenance:

```console
touch /var/lib/stb-maintenance
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  https://www.societe-de-tir-bertrix.com/
```

The curl command must print `503`. Remove the marker only after backend,
database, backup, and public checks pass:

```console
rm /var/lib/stb-maintenance
```

## Backup verification

Create and inspect an atomic database dump:

```console
systemctl start stb-mariadb-dump.service
systemctl show --property=Result --value stb-mariadb-dump.service
test -s /nix/var/data/backup/stb_mariadb.sql
stat -c '%n %a %U:%G %s bytes' /nix/var/data/backup/stb_mariadb.sql
```

The result must be `success` and the dump mode must be `600`.

Run a fresh Borg archive, repository check, and restore extraction:

```console
systemctl start borgbackup-job-data.service
systemctl start borgbackup-check-data.service
systemctl start borgbackup-restore-test-data.service
systemctl show --property=Result --value \
  borgbackup-job-data.service \
  borgbackup-check-data.service \
  borgbackup-restore-test-data.service
```

All three results must be `success`. The restore test verifies that the latest
archive contains a non-empty STB database dump.

## Database restore

Use a logical dump, never MariaDB 10.x physical files.

1. Enable maintenance mode and stop WordPress.
2. Take a safety copy of the current database and WordPress files.
3. Recreate the `stb` database with the current root secret.
4. Import the selected dump through the rootless MariaDB container.
5. Start WordPress and verify the backend before removing maintenance mode.

The import command reads the application password from the mounted secret:

```console
systemctl stop podman-stb-wordpress.service
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman exec --interactive stb-mariadb sh -ceu '
    credentials="$(mktemp)"
    trap "rm -f \"$credentials\"" EXIT
    {
      printf "[client]\nuser=stb\npassword="
      cat /run/secrets/stb-database-password
      printf "\n"
    } > "$credentials"
    mariadb --defaults-extra-file="$credentials" stb
  ' < /path/to/stb.sql
```

When restoring WordPress files from a source that does not preserve the
rootless namespace ownership, hand them to `stb` before mapping them to the
container's `www-data` identity:

```console
chown -R stb:stb /nix/var/data/stb-wordpress
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman unshare chown -R 33:33 /nix/var/data/stb-wordpress
env --chdir=/var/lib/stb runuser --user stb -- \
  env HOME=/var/lib/stb XDG_RUNTIME_DIR=/run/user/5001 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/5001/bus \
  podman unshare chown 0:33 /nix/var/data/stb-wordpress/wp-config.php
chmod 0440 /nix/var/data/stb-wordpress/wp-config.php
```

The static homepage hero is mounted read-only from
`modules/stb/static-hero.php` and does not need to be restored from WordPress
data.

## Credential rotation

Changing SOPS values does not update accounts inside an initialized MariaDB
database. Never rotate these files through an ordinary deployment alone.

1. Enable maintenance mode and create a fresh atomic dump.
2. Generate independent replacement application and root passwords without
   placing them in shell history or process arguments.
3. Connect with the current root secret and run `ALTER USER` for `stb@%` and
   `root@localhost`.
4. Update `stb/database_password` and `stb/database_root_password` in
   `secrets.enc.yml`.
5. Deploy and restart `prepare-stb-wordpress-secret.service`, MariaDB, and
   WordPress.
6. Verify application access and the atomic dump before removing maintenance.

If deployment or verification fails, restore the previous account passwords
before removing maintenance mode.

## Image and application updates

OCI digests are immutable and do not update automatically. At least monthly:

1. Review WordPress/PHP and MariaDB release notes.
2. Update both tag-and-digest references in `modules/stb.nix`.
3. Restore current WordPress files and a logical database dump into an isolated,
   loopback-only staging environment.
4. Prevent staging email delivery and disable WP-Cron.
5. Test login, administration, uploads, forms, active plugins, the custom
   `sport` theme, container restarts, and reduced capabilities.
6. Deploy only the versions accepted in staging.

Slider Revolution 5.4.3.1 and Timetable 3.8 were removed because they are
obsolete and incompatible with PHP 8.3. The single Slider Revolution homepage
slide is replaced by `modules/stb/static-hero.php`.

The persistent custom theme/plugin files include the fixes recorded in
`modules/stb/wordpress-7.1-compat.patch`. Current Borg restores preserve those
files. Reapply and retest the patch after restoring pre-migration files or
updating the custom `sport` theme or `sport-core-plugin`. Stop WordPress and
apply it before the rootless ownership mapping:

```console
patch --directory /nix/var/data/stb-wordpress --strip=1 \
  < modules/stb/wordpress-7.1-compat.patch
```

Do not force the patch if its context no longer matches. Review the upstream
changes and create a new compatibility patch instead.

## Temporary rollback

Keep this section only while the pre-migration assets remain on `hel1`:

| Item | Value |
| --- | --- |
| Previous NixOS generation | `180` |
| Legacy MariaDB directory | `/var/lib/mariadb/stb` |
| Pre-cutover snapshot | `/nix/var/data/stb-migration/20260826T185418Z` |

The previous generation does not understand the persistent maintenance marker.
Mask nginx for the complete rollback transition:

1. Create `/var/lib/stb-maintenance` and stop the rootless containers.
2. Run `systemctl mask --runtime --now nginx.service`.
3. Move the current WordPress directory aside and restore the snapshot's
   `wordpress` directory to `/nix/var/data/stb-wordpress`.
4. Switch `/nix/var/nix/profiles/system` to generation 180 and activate it.
5. Start the old rootful pod against the untouched legacy MariaDB directory.
6. Validate the old backend directly on `127.0.0.1:8180`.
7. Remove the marker, unmask nginx, and start nginx.

Do not reboot during rollback because the runtime nginx mask is volatile. Keep
the failed current WordPress directory and new MariaDB directory until rollback
verification completes.

After the production acceptance period, explicitly remove generation 180, the
legacy MariaDB directory, and both migration snapshots. Do not remove them as
part of an ordinary deployment.

## Migration record

The production migration completed on 2026-08-26. WordPress was upgraded from
4.9.4 to 7.1, PHP from 7.4.27 to 8.3.33, and MariaDB from 10.7.8 to 11.4.13.
The WordPress database schema, maintained plugins, persistent-file ownership,
atomic dump, Borg archive, repository check, restore extraction, and a full
dump import were verified. Manual staging checks accepted the replacement
homepage hero before production cutover.
