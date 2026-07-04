# NixOS 26.05 Upgrade Design

## Goal

Update the self-hosting flake from NixOS 25.11 to 26.05 while handling release-note prerequisites for the services in use.

## Scope

- Update `nixpkgs` to `nixos-26.05`.
- Update `simple-nixos-mailserver` to the matching 26.05 input if available.
- Replace removed `services.promtail` with Grafana Alloy for Loki ingestion.
- Fix known 26.05 evaluation blockers: explicit bind mount `fsType`, Grafana `security.secret_key`, and PostgreSQL target dependencies.
- Keep PostgreSQL and Nextcloud major versions pinned during this OS upgrade.

## Service Changes

- Alloy will read the systemd journal and nginx logs, then forward logs to the local Loki endpoint.
- Grafana will use a SOPS-backed `security.secret_key` to preserve encrypted settings and sessions.
- Nextcloud keeps `pkgs.nextcloud32`; only the bind mount declaration changes.
- PostgreSQL remains pinned to `pkgs.postgresql_15`; dependent setup units wait for `postgresql.target`.

## Runtime Prerequisites

- Confirm Immich has completed the pgvecto.rs to VectorChord migration before deploying 26.05.
- Use remote console or rescue access for first reboot because 26.05 defaults to systemd initrd.
- Reboot after deploying because D-Bus implementation changes are a switch inhibitor.

## Verification

- Run formatting on changed Nix files.
- Build/evaluate both `hel1` and `relay1` NixOS configurations.
- Run deploy checks if evaluation succeeds.
- After deployment, validate Loki ingestion, Grafana login, nginx, mail, Matrix/TURN, Immich, Nextcloud, containers, relay routing, and backups.
