# Pangolin architecture

## Topology

`pangolin1` hosts Pangolin, Gerbil, and Traefik. The control-plane endpoint and
dashboard are <https://pangolin.banditlair.com>. Newt connectors connect outbound
to the gateway and originate connections to site resources.

| Site | Resources |
| --- | --- |
| `hel1` | Grafana, Monero RPC, Uptime Kuma, host SSH |
| `relay1` | Host SSH, conditional DNS, Foyer WSL, six Foyer network ranges |
| `aegis` | Home router SSH and AdGuard administration; configured in `nixos-configs` |

`relay1` reaches Foyer through its existing WireGuard-over-wstunnel link.
Client traffic uses direct tunnels where possible or Gerbil relay connections;
relay connectivity still requires UDP, with no HTTPS fallback.

The Aegis configuration declares one private host resource, allowing TCP ports
`22,3000` through `aegis.home.internal`, with UDP and ICMP disabled. Its destination
is `aegis-target.home.internal`, resolved by a hosts entry on Aegis to
`192.168.1.1`. A hostname destination prevents Pangolin from advertising a raw
`192.168.1.1/32` route that would capture clients' local router traffic. It does
not grant access to the home LAN subnet or change the router's firewall, DNS
listeners, or Mullvad routing; the hosts entry may also be served by LAN DNS.
The connector follows the router's existing egress; no Mullvad bypass is
configured. Enrollment and deployment instructions
are in the `nixos-configs` README. Credentials are encrypted for Aegis's existing
SSH host identity and the operator recovery key; sops-nix installs them at runtime.

### Aegis verification (2026-09-19)

The site is online and its configuration is persisted. Verified SSH through
`aegis.home.internal` against the existing LAN host key, AdGuard's login redirect
and unauthenticated API rejection, and recovery after restarting Newt. The private
resource grants only `Personal` and `Admin`, with no individual user grants.
TCP and UDP DNS requests through the alias are blocked, while normal LAN DNS
works and clients no longer receive a raw router `/32` route. The SOPS environment
file is root-owned with mode `0400`; no failed units or enrollment rollback timers
remain. Mullvad stayed disabled during live verification; VPN transitions and
failure injection were not exercised.

## Access boundaries

Newt blueprints declare resources and role grants; account membership is managed
in Pangolin. Blueprint users remain empty to keep identities out of the repository.

| Role | Access |
| --- | --- |
| Personal | All declared private resources; owner's daily non-admin account |
| Member | Uptime Kuma; separate family and friend accounts |
| Admin | Automatic organization-wide access; separate management account |

All devices on an account inherit its access. Blueprint keys identify persistent
resources; removing a declaration does not delete the resource from Pangolin.

Host SSH resources `hel1.bl.internal` and `relay1.bl.internal` target local
`127.0.0.1:22`. OpenSSH retains key authentication; Newt's built-in SSH is disabled.
`relay1` blocks public SSH. `hel1` retains public SSH for CI, Borg, and Nix store
clients, but allows root login only from loopback. Loopback is not exclusive to
Newt: local processes and the authenticated Chisel proxy can also reach it.
The trusted Nix store user is already root-equivalent.

## HTTPS and DNS

Public DNS for private HTTP resources points to `pangolin1`, which serves a
placeholder rather than the application. Connected clients resolve private
addresses, and Newt terminates HTTPS at the site. Traefik obtains certificates
through HTTP-01; a private ACME-state mirror lets Pangolin distribute them to Newt.

Client split DNS covers the configured Foyer zones, `*.internal`, and
`*.banditlair.com`. Pangolin answers resource aliases first; matching misses go
through the private DNS resource to Unbound on `relay1` at `127.0.0.1:53`.
Other queries use the client's normal resolver.

Unbound forwards `foyer.cloud`, `foyer.lu`, `lefoyer.lu`, and `internal` to
`10.33.0.100`, with DNSSEC validation disabled for those internal zones. Other
queries go to Quad9 with validation enabled. The client's upstream is the DNS
resource's numeric tunnel IP, not loopback; it is database-assigned, not reserved.
Matching DNS misses, including the gateway hostname, therefore depend on `relay1`.

## Resource naming

Infrastructure aliases use `<hostname>.<group>.internal`. Keep them short and
match the NixOS `networking.hostName`, including any environment suffix.
Functional aliases such as `dns` and `wsl` identify a service or endpoint and
remain stable when its underlying host changes.
Group codes describe logical ownership, not access roles or physical location:

| Group | Scope |
| --- | --- |
| `bl` | Bandit Lair infrastructure |
| `home` | Home infrastructure |
| `ov` | Osteoview infrastructure |
| `foyer` | Foyer access endpoints |

| Resource | Alias |
| --- | --- |
| Hel SSH | `hel1.bl.internal` |
| Relay SSH | `relay1.bl.internal` |
| Aegis management | `aegis.home.internal` |
| Conditional DNS | `dns.bl.internal` |
| Foyer WSL | `wsl.foyer.internal` |
| Osteoview staging bastion | `bastion1-staging.ov.internal` |
| Osteoview production bastion | `bastion1-production.ov.internal` |

Existing application URLs, including `grafana.banditlair.com`,
`uptime.banditlair.com`, and `monero.banditlair.com`, remain unchanged. The gateway
stays at `pangolin.banditlair.com`. Keep the existing `*.internal` and
`*.banditlair.com` split-DNS coverage and the authoritative Foyer zones.

An alias rename must preserve the blueprint key, resource ID, ports, and grants.
Update deployment hostnames and workstation consumers together, retaining the
existing SSH `HostKeyAlias`. In Pangolin 1.22.2, alias-only updates to an existing
host resource preserve its virtual IP; deletion/recreation does not guarantee it.
Before deploying a connector rename, resolve its current alias and verify SSH to
that numeric tunnel IP with strict host-key checking. Use the verified IP as the
temporary deploy-rs `--hostname` override for building and dry activation. Do not
hard-code these IPs as permanent host addresses.

Restarting Newt closes its proxied SSH connections, including deploy-rs's
confirmation waiter. A longer confirmation timeout does not reconnect that
waiter. For a rename without an independent SSH transport, first schedule a
host-local rollback timer restoring the old system profile and configuration.
Run the new configuration's `switch-to-configuration test` in a detached systemd
unit, reconnect through the verified IP or new alias, and check service health.
Keep the activation unit's exit status available with `RemainAfterExit=yes` and
allow 15 minutes for verification. If verification fails, leave rollback armed.
After verification succeeds, stop the timer before persisting to avoid racing
rollback, then set the system profile and run `switch-to-configuration switch`.
If persistence fails, restore the recorded old profile/configuration explicitly.
Verify both the running system and saved profile point to the new configuration.
Process hosts one at a time; do not disable rollback protection just to avoid an
SSH disconnect.

The workstation's numeric DNS upstream remains unchanged when `dns` is renamed.
The Foyer proxy upstream in `nixos-configs/modules/services/work-proxy.nix` must
use `wsl.foyer.internal`; activate that consumer after renaming the relay resource.

### Migration verification (2026-09-14)

All five infrastructure aliases are deployed. Their virtual IPs remained
unchanged, and the client alias list contains only the new names. Verified SSH
to Hel, relay, and the staging bastion with their existing host-key identities,
plus a database jump through the renamed staging bastion. Conditional DNS works
over TCP and UDP. The updated workstation proxy reaches Microsoft sign-in
through `wsl.foyer.internal`.

Grafana health and Monero RPC returned HTTP 200; Uptime Kuma returned its normal
HTTP 302 and the Pangolin dashboard HTTP 200 at their unchanged URLs. Hel and
relay have matching running/saved configurations, no failed systemd units, and
no remaining migration rollback timers. No public DNS, firewall, resource grants,
or production Osteoview configuration was changed by this rename.

## Dependencies and recovery

SSH deployment targets use the private aliases and preserve existing host-key
identities. Management depends on Pangolin and Newt; restarting a connector
interrupts its management path. Provider rescue and independently held SOPS keys
are the recovery boundary. Fresh `relay1` provisioning requires staged public
SSH access and working host-key/SOPS bootstrap before closing its firewall.

Osteoview bastions retain their public DNS/IP allocations, but their attached
Hetzner firewalls have no ingress rules. Public SSH is closed in both environments,
and both restricted `/32` API recovery paths have been verified. Bastion deployments
must use Osteoview's guarded
`deploy-bastion.sh` over the private alias, not deploy-rs directly. Emergency
public SSH is an explicit temporary HCloud API rule restricted to the operator's
current IPv4 `/32` (or IPv6 CIDR), followed by strict host-key SSH and explicit
deletion of the identical rule. This path uses locally held SOPS/admin
credentials and does not depend on Pangolin. Console/rescue and cold-OS-failure
drills remain untested.

Gateway backups contain a consistent SQLite snapshot, application secrets,
Gerbil key, ACME state, and RSA host key. Borg access is repository-restricted and
append-only; Hetzner VM backups are supplementary. Automated restore checks
validate extracted files, not complete replacement-host recovery.

## Configuration sources

| Concern | Source |
| --- | --- |
| Gateway and backups | [`profiles/pangolin1.nix`](../profiles/pangolin1.nix) |
| Services and certificate synchronization | [`modules/pangolin.nix`](../modules/pangolin.nix) |
| Site resources and SSH policies | [`profiles/hel.nix`](../profiles/hel.nix), [`profiles/relay1.nix`](../profiles/relay1.nix) |
| Deployment targets | [`flake.nix`](../flake.nix) |
| Packages and VM test | [`packages/pangolin/`](../packages/pangolin/) |
| Provisioning and public DNS | [`terraform/`](../terraform/) |
| Encrypted secrets | `secrets/pangolin.enc.yml`, `newt` in `secrets.enc.yml` |
| Gateway host-key bootstrap | [`scripts/pangolin-extra-files.sh`](../scripts/pangolin-extra-files.sh) |
| Client DNS and proxy | `nixos-configs/modules/services/work-proxy.nix` in the workstation repository |
| Home router connector | `nixos-configs/hosts/aegis/newt.nix` in the workstation repository |
| Home router credentials | `nixos-configs/secrets/aegis-newt.enc.yml`; sops-nix decrypts it using Aegis's SSH host identity |
