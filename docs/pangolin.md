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
| Private Uptime Kuma, Grafana, and Monero resources on `hel1` | [`profiles/hel.nix`](../profiles/hel.nix) |
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
| Foyer | Foyer WSL, six work-network ranges, and conditional DNS | `[ "Personal" ]` |
| Shared | Uptime Kuma and future shared services | `[ "Personal" "Member" ]` |
| Personal | Grafana, Monero, future accounting, and other owner-only services | `[ "Personal" ]` |

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

When migrating an existing public hostname, apply its DNS change to `pangolin1`
first and allow the previous TTL to expire. Then deploy
the Newt resource and remove the old public proxy. This avoids starting HTTP-01
validation while requests still reach the old host. Public application access stops
during this cutover. Verify certificate issuance and authorized client access
afterward, and update any external uptime probes: Pangolin's public placeholder
is not evidence that the private application is healthy.

Manage resources and grants in Newt blueprints, not the dashboard. Reapplication
replaces declared resources' settings, labels and user, machine and non-admin role
grants. Pangolin preserves its automatic organization Admin grant. Account
memberships remain manually managed in Pangolin.

Blueprint keys are stable resource identifiers. Removing an entry does **not**
delete the server resource; retirement also requires explicit deletion in
Pangolin. After deployment, check Newt's journal and the applied resource state,
then test access: successful NixOS activation alone does not prove acceptance.

Keep WireGuard and wstunnel on `relay1`; Newt uses that route to the work network.

## Monero RPC

`https://monero.banditlair.com` is a private resource routed through the `hel1`
Newt connector to `127.0.0.1:18081`. Access requires a connected **Personal**
client; Pangolin's automatic organization Admin grant also applies. Monero's
restricted RPC mode is enabled, and Pangolin controls remote client access.

To check RPC health, run from an authorized connected client and verify that
the response contains a `get_info` RPC result, not Pangolin's public placeholder:

```console
curl --fail-with-body -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  https://monero.banditlair.com/json_rpc
```

## Conditional DNS

Unbound on `relay1` listens only on `127.0.0.1:53`. The Newt host resource
`conditional-dns` targets that address, permits only TCP and UDP port 53, and
makes the loopback listener available through the tunnel. Restrict it to the
**Personal** role. Do not expose port 53 publicly or change `relay1`'s own host
resolver to use Unbound.

Unbound forwards the `foyer.cloud.`, `foyer.lu.`, `lefoyer.lu.`, and `internal.`
zones to `10.33.0.100`; all other queries reaching it go to Quad9 at `9.9.9.10`
and `149.112.112.10` (the unfiltered service, over ordinary DNS). DNSSEC validation
is disabled only for those four forwarded zones to trust Foyer's split-horizon
answers; public answers remain locally validated by Unbound.

The laptop configuration is:

```nix
home.file.".config/pangolin/config.json".text = builtins.toJSON {
  up = {
    override_dns = true;
    tunnel_dns = true;
    upstream_dns = [ "100.96.128.11:53" ];
    match_domains_dns = [
      "foyer.cloud"
      "*.foyer.cloud"
      "foyer.lu"
      "*.foyer.lu"
      "lefoyer.lu"
      "*.lefoyer.lu"
      "*.internal"
      "*.banditlair.com"
    ];
  };
};
```

The `banditlair.com` apex is deliberately omitted; the wildcard covers subdomains.
Private resources under other suffixes still need matching entries.
For a matching query, Pangolin checks its own resource and alias records first;
if none matches, it sends the query through `conditional-dns` to Unbound. A
query outside `match_domains_dns` continues to use the laptop's normal DNS.
Use the resource's tunnel-visible virtual IP as the upstream, not its site-side
destination `127.0.0.1`. CLI 0.15.1 / Olm 1.8.2 does not translate a loopback
upstream into the resource's virtual IP. The `dns.internal` alias currently
resolves to `100.96.128.11`; queries to that IP reach Unbound on `relay1`.
Use the numeric IP, not the alias hostname, to avoid DNS bootstrap dependencies.

The virtual IP is stored in Pangolin's database and survives reconnects,
restarts, and blueprint updates to the same resource. It is not a pinned
reservation: after deleting/recreating the resource or rebuilding the database,
check `dig +short dns.internal A` from an authorized connected client and update
the laptop upstream if necessary. Before activation, verify both public and
Foyer resolution with `dig @100.96.128.11 jellyfin.banditlair.com` and
`dig @100.96.128.11 foyer.cloud`.

While connected, all matching DNS misses depend on `relay1`, including queries
for `pangolin.banditlair.com`. If tunnel DNS fails and prevents reconnection, run
`pangolin down` to restore normal DNS before reconnecting. If `relay1` remains
unavailable, remove the Bandit Lair wildcard from the client defaults temporarily
to recover public access; private resource resolution will be unavailable for
that suffix. Test this recovery path before relying on the setup remotely.

Authorize and apply `conditional-dns` before activating the laptop configuration.
For the systemd-managed laptop client, rebuild its configuration and restart
`pangolin.service` to load the new upstream; do not start a second CLI session.
For a manually managed client, reconnect with `pangolin down` followed by
`pangolin up`. On `relay1`, check the services,
loopback-only listener, public recursion, and a Foyer answer:

```console
sudo systemctl status unbound newt
sudo ss -lntup 'sport = :53'
nix shell nixpkgs#bind nixpkgs#tcpdump
dig @127.0.0.1 example.com
dig @127.0.0.1 foyer.cloud
dig @127.0.0.1 cloudflare.com +dnssec
dig @127.0.0.1 dnssec-failed.org
```

The signed public answer should carry the `ad` flag; `dnssec-failed.org` should
return `SERVFAIL`. Use a known internal Foyer hostname as well as the apex to
check split-horizon resolution.

On the connected client, compare private Pangolin resources, a Foyer name,
a public Bandit Lair host, and an unrelated public host:

```console
dig grafana.banditlair.com
dig foyer-wsl.internal
dig foyer.cloud
dig pangolin.banditlair.com
dig example.com
```

Verify that Grafana resolves to a Pangolin private address, not its public
placeholder, and that authenticated HTTPS access actually reaches Grafana.
Verify WSL SSH access too. Public Bandit Lair misses must go to Quad9, whereas
`example.com` uses the laptop's normal DNS. DNS answers alone do not prove the
forwarding path: on `relay1`, use
`sudo tcpdump -ni any 'port 53 and (host 10.33.0.100 or host 9.9.9.10 or host 149.112.112.10)'`
while issuing uncached queries. Foyer queries must go only to `10.33.0.100`,
and public Bandit Lair misses must never go there.

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
