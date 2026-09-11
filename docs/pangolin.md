# Pangolin operations

Dashboard: <https://pangolin.banditlair.com>. The gateway runs on `pangolin1`;
Newt connectors run on `relay1` and `hel1`.

## Configuration

| Concern | Source |
| --- | --- |
| Gateway, secrets and backup settings | [`profiles/pangolin1.nix`](../profiles/pangolin1.nix) |
| Native services and certificate synchronization | [`modules/pangolin.nix`](../modules/pangolin.nix) |
| Pinned packages and VM test | [`packages/pangolin/`](../packages/pangolin/) |
| Work-network and WSL resources | [`profiles/relay1.nix`](../profiles/relay1.nix) |
| Private Uptime Kuma resource | [`profiles/hel.nix`](../profiles/hel.nix) |
| VM provisioning and public DNS (OpenTofu) | [`terraform/`](../terraform/) |
| Workstation DNS and proxy | `nixos-configs/modules/services/work-proxy.nix` in the workstation repository |

Gateway secrets are in `secrets/pangolin.enc.yml`; connector credentials are
under `newt` in `secrets.enc.yml`. Keep decrypted secrets out of logs and Git.
`scripts/pangolin-extra-files.sh` restores the encrypted RSA host key before sops-nix
decrypts runtime secrets. Keep administrator SOPS access independent of the VM.

## Access separation

Community Edition permits one role per user. Use **Personal** only for the
owner's daily non-administrator account; family and friends use their own
**Member** accounts. Keep the separate
**Admin** account for management: Pangolin grants administrators access
automatically, so daily accounts must have no administrator privileges.

| Resource group | Resources | Blueprint `roles` |
| --- | --- | --- |
| Foyer | Foyer WSL and six work-network ranges | `[ "Personal" ]` |
| Shared | Uptime Kuma and future shared services | `[ "Personal" "Member" ]` |
| Personal | Future accounting and other owner-only services | `[ "Personal" ]` |

Every device belonging to the daily account inherits all of that account's access.
Assigning Member grants access to all shared resources, including future ones.

Keep blueprint `users` empty: identities would otherwise appear in the public
repository and generated Nix store files. Manage account membership in Pangolin,
not in a blueprint. Before deployment, create the non-administrator Personal role
with the default Member-equivalent permissions, then replace the daily account's
Member assignment with Personal.

After deployment, check Newt's journal for successful blueprint application.
Confirm that the daily account has only Personal and no server-admin privileges,
then connect a client with it and verify work and shared access. Confirm that a
distinct non-admin Member account can reach shared resources but not work
resources. Reapply the blueprints and repeat those checks to confirm that
separation persists.

## Resource changes

Manage resources and grants in Newt blueprints, not the dashboard. Reapplication
replaces declared resources' settings, labels and user, machine and non-admin role
grants. Pangolin preserves its automatic organization Admin grant. Account
memberships remain manually managed in Pangolin.

Blueprint keys are stable resource identifiers. Removing an entry does **not**
delete the server resource; retirement also requires explicit deletion in
Pangolin. After deployment, check Newt's journal and the applied resource state,
then test access: successful NixOS activation alone does not prove acceptance.

Include new private hostnames in the client's DNS match list. Reconnect with
`pangolin down` followed by `pangolin up` after changing connection defaults.
Keep WireGuard and wstunnel on `relay1`; Newt uses that route to the work network.

## HTTPS and connectivity

Traefik obtains certificates through HTTP-01. Public DNS for private HTTP
resources points to `pangolin1`, which serves a placeholder, not the application.
Connected clients resolve the private address; Newt terminates HTTPS at the site.

`pangolin-acme-cert-sync.timer` copies validated Traefik ACME state atomically
to `/var/lib/pangolin/config/acme-sync/acme.json`. The source stays private to
Traefik; the mirror is private to Pangolin. Both files must remain mode `0600`.
Pangolin imports the mirror and distributes certificates to Newt.

Check `pangolin`, `gerbil`, `traefik`, the certificate-sync unit and Monit when
troubleshooting. Native backend listeners are not all loopback-bound: preserve
their firewall restrictions. Do not expose them to work around a proxy failure.
Traefik's Badger plugin fetch needs outbound DNS/HTTPS during a cold startup.

`pangolin status` distinguishes local/direct and relay connections. To test
fallback, reconnect with `pangolin up --holepunch=false` and confirm **Relay**
before testing resources. Reconnect normally afterward. Relay still needs UDP;
it does not provide Tailscale's HTTPS fallback on UDP-blocked networks.

## Backup and recovery

The database recovery artifact is `nix/var/data/backup/pangolin.sqlite` inside
the Borg archive. Live SQLite/WAL files and reproducible `.next` contents are
excluded. Other recovery inputs include the application environment, Gerbil key,
ACME state and RSA host key. Paths are in the host profile; schedules default in
[`modules/backup-job.nix`](../modules/backup-job.nix). Hetzner VM backups provide
an additional recovery option, not a substitute for a consistent database backup.

The gateway's Borg key is repository-restricted and append-only. Pruning does
not reclaim space; compaction requires separate trusted administrative access.
Verify archive history and run `borg check --verify-data` before compaction,
which can permanently remove data previously only logically deleted.

The repository key, passphrase and transport key are stored under
`borg/repository_key`, `borg/passphrase` and `borg/ssh_key` in the gateway's SOPS
file. Use the pinned Storage Box host key from the host profile. To recover lost
repository-key metadata, feed the exported key to `borg key import REPOSITORY -`
without displaying it; the original passphrase is still required.
Do not reinitialize an existing repository. The automated restore test validates
extracted files, not a complete replacement-host boot.

### Database restore

1. Extract the snapshot from a verified Borg archive into a root-only temporary directory. Require
   `test -s "$RESTORED_SNAPSHOT"` to succeed, then verify that
   `sqlite3 -readonly "$RESTORED_SNAPSHOT" 'PRAGMA quick_check;'` returns exactly `ok`.
2. Stop `traefik`, `gerbil`, `pangolin`, and the certificate-sync timer/service.
   Confirm they are inactive, and safety-copy the current database and any
   `db.sqlite-wal` / `db.sqlite-shm` sidecars before replacing anything.
3. With writers stopped, remove the stale sidecars and install the snapshot at
   `/var/lib/pangolin/config/db/db.sqlite`, owned by `pangolin:fossorial`, mode
   `0600`. Verify integrity again. Preserve or restore the matching `SERVER_SECRET`
   and supporting keys; never generate replacements during recovery.
4. Start Pangolin, Gerbil, Traefik and the certificate-sync timer. Check service
   health, client connectivity and private HTTPS before discarding safety copies.

On a replacement host, the Gerbil first-start workaround may require the restored
`/var/lib/pangolin/config/wg0` marker to be absent. Assess this before first
startup only when necessary. Never remove it during a routine restore or on a
functioning host.

## Retired Headscale

Rollback state is retained on `hel1` at `/var/lib/headscale` and in the root-only,
Borg-backed `/nix/var/data/backup/headscale-retired-2026-09-11/` archive directory.
The dormant Headscale module remains available. Rollback requires restoring its
enablement, DNS, and the clients' Tailscale routing/NAT declarations, not merely
starting a daemon. Prefer targeted configuration changes over a whole-generation
rollback that could restore unrelated old behavior. Keep the saved keys intact.
