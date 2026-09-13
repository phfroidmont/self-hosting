# Pangolin architecture

## Topology

`pangolin1` hosts Pangolin, Gerbil, and Traefik. The control-plane endpoint and
dashboard are <https://pangolin.banditlair.com>. Newt connectors on `hel1` and
`relay1` connect outbound to the gateway and originate connections to site resources.

| Site | Resources |
| --- | --- |
| `hel1` | Grafana, Monero RPC, Uptime Kuma, host SSH |
| `relay1` | Host SSH, conditional DNS, Foyer WSL, six Foyer network ranges |

`relay1` reaches Foyer through its existing WireGuard-over-wstunnel link.
Client traffic uses direct tunnels where possible or Gerbil relay connections;
relay connectivity still requires UDP, with no HTTPS fallback.

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

Host SSH resources `hel1.internal` and `relay1.internal` target local
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

## Dependencies and recovery

SSH deployment targets use the private aliases and preserve existing host-key
identities. Management depends on Pangolin and Newt; restarting a connector
interrupts its management path. Provider rescue and independently held SOPS keys
are the recovery boundary. Fresh `relay1` provisioning requires staged public
SSH access and working host-key/SOPS bootstrap before closing its firewall.

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
