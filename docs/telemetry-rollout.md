# Central telemetry rollout

## Deployment status

| Environment | Sources | Remote scrape targets | Legacy ingestion | Cutover verification |
| --- | --- | --- | --- | --- |
| Staging | 7, all healthy | 11, all up | Disabled; historical queries retained | 2026-09-26 11:42:59 UTC |
| Production | 7, all healthy | 11, all up | Disabled; historical queries retained | 2026-09-26 18:27:46 UTC |

Both environments now admit all 14 sources. All 27 central Prometheus targets
were healthy: 22 remote (14 node, four nginx, four application) and five local.
Fresh 15-minute Loki heartbeat queries found all 14 distinct
`environment`/`host` pairs. At final audit every source had one central writer,
zero legacy writers and `droppedEntries=0` since its final collector activation.
This does **not** mean no log was ever lost: the initial pilot's two central
drops, preserved in legacy logs, remain part of the historical record. The
production demo is outside this migration's existing 14-source coverage.

In **both** environments the old metrics VM has zero ingestion/scrape targets,
old Grafana has `execute_alerts=false`, and old Loki HTTP listens on loopback.
Query services, data volumes and VMs remain: after each cutover, historical
`count(up)` returned 12 and the historical nginx log count was positive. Review
retirement of **both** on **2026-11-25** (60 days), not automatic deletion.
Idle Prometheus retention is not a wall-clock expiry; old Loki's rolling 60-day
compactor continues clearing old logs as requested. No Terraform deletion has
been applied. At review, confirm history and user approval first, then plan
removal of old metrics VMs/exporters, inventory, grants and DNS carefully; do
not remove query services or volumes before the review.

The paired rollout lists control source admission. The application repository's
`nix/telemetry-cutover.nix` controls legacy shipping, old scrapes and old alert
execution independently for staging and production; it refuses premature cutover.

## Central services and notifications

- Grafana: `https://grafana.banditlair.com/`, through the existing private access.
- Preserved datasource UIDs: Prometheus `PBFA97CFB590B2093`, Loki
  `P8E80F9AEF21F6940`.
- Nodes dashboard UID `xfpJB9FGz`; Request Handling Performance UID `4GFbkOsZk`.
  Environment/instance selection separates the fleets. The new request dashboard
  is provisioned in Grafana's `dashboard.grafana.app` resource table, not the
  legacy SQL `dashboard` table.
- Metrics retain 180 days; logs retain 365 days.
- Existing disk, RAM, CPU and failed-unit alerts are centralized, with additional
  expected-target and journal-heartbeat checks. All 41 central Grafana alert-rule
  UIDs were verified. The private watchdog checks the central query/evaluation
  chain independently.
- Source heartbeats use a five-minute systemd timer and stdout-backed journal
  entries carrying `unit="telemetry-heartbeat.service"`.
- The private watchdog uses hel1's existing machine client and relay1's Newt,
  with a dedicated loopback proxy and receiver. No new public listener was added.
- Alert-email credentials and the watchdog token were prepared by the operator
  into `secrets/telemetry-alerts.enc.yml`; they were not exposed to the assistant.

During a controlled seven-minute telemetry-client outage, the operator confirmed
receipt of both the central Grafana staging failure email and the independent
relay watchdog failure email. Recovery was automatic; Grafana sent its recovery
notification and authenticated watchdog heartbeats resumed. The operator later
confirmed production canary failure **and recovery** emails. No plaintext SMTP
credential or watchdog token was read into the assistant session.

## Checks and operational findings

- Both database leaders stayed unchanged (staging node2, production node1),
  with two streaming replicas each at zero reported lag. No Patroni or etcd
  restart was needed. Application health checks returned HTTP 200; all source
  targets were healthy at final verification. The private application proxy accepts only the intended
  metrics request from the bastion.
- A synthetic nginx request was delivered once to each Loki destination. A
  separate synthetic file's pre/post-rotation records reached both destinations;
  that probe file was removed afterward.
- Alloy 1.12's legacy journal converter uses `labels={}` instead of `labels=""`.
  The helper seeds only missing native positions in `/var/lib/alloy/data-alloy`;
  a VM test covers migration without replay, restart and central-only cutover.
  Heartbeats write to stdout (rather than `logger`) for a reliable unit label.
  Whole-file/unit `mkIf` guards prevent phantom configuration on unselected hosts.
- Hetzner's private NIC order differs on some database hosts. The temporary
  legacy exception permitted only the exact old Loki IP and port 3100 over
  `eth1` or `eth2`, never public `eth0`. Staging DB1/3 buffered queues drained
  with matching central/legacy entries and zero drops. Both cutovers removed
  the exceptions. Backup node exporter ingress now permits only both private
  interfaces (`eth1`/`eth2`), not global 9100; an untrusted third interface was
  denied in the VM test.
  A narrow temporary bastion-only INPUT rule was removed after that declarative
  fix; production backup needed the second private interface too.
- The Pangolin first-apply cache workaround remains documented in
  [the pilot record](telemetry-pilot.md). It also affected the production
  collector-to-site grant; one unchanged Newt reapply repaired it without DB
  writes or broader roles. Use it only when the observed gap matches, and verify
  effective access afterward.
- Treat Alloy's native positions as persistent state. Do not reset them without
  reviewing the retained migration snapshot: a missing native cursor can be
  reseeded from an old Promtail cursor. A deliberate reset should disable the
  legacy-position import first and explicitly choose the replay window.
- Public SSH scan traffic on hel1 occasionally hits sshd's global `MaxStartups`
  limit, including its loopback Newt connection. Reuse an authenticated SSH
  connection (ControlMaster was used) and retain host-local, detached PID 1
  rollback protection when restarting connectors. SSH policy was not changed.

Final hel1 current/saved system and profile:
`/nix/store/66a9xxkbx6vy8zr5zs13sxppnqhn0i16-nixos-system-hel1-26.05.20260820.5880666`;
relay1: `/nix/store/anpjsqvh1ms349qp0w2i8mcmx5wcxmbx-nixos-system-relay1-26.05.20260820.5880666`.
Hel1 had no failed units or pending telemetry-deploy timers. Relay Newt, monit
and receiver were active with fresh heartbeat and no pending timers. Final
hel1 free NVMe was 452 GiB and available RAM 49 GiB. The pilot's ~120 MiB Alloy
and 18 MiB Olm snapshot is **not** a full-fleet benchmark.

The temporary controller transaction helper at
`/nix/store/9nvb0hp2hp7dmr3acdmixsqprbv8aby5-private-telemetry-transaction.sh`
has `begin/status/confirm/rollback HOST NEWSYS` via bash PATH, records GC roots
and host/hash, and requires a real Nix system path (not a wrapper). It is an
ephemeral ops aid, not a maintained repository interface or a substitute for
reviewing rollback state. Bastions still require `deploy-bastion.sh`.

Private GitLab artifacts returned 401 locally; the exact runtime packages were
cached on the backend hosts. Build those closures there (`--remote-build`)
rather than requesting a GitLab token or relaxing Nix signature verification.
Hel1 builds on-host to reuse its cached Foundry package. No reboot or VM deletion
was part of this rollout.
