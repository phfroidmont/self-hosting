# Telemetry pilot: historical snapshot and expansion gates

**Historical record, not current rollout instructions.** The status and gates
below describe the 2026-09-25 pilot and are preserved to document what was
actually observed (including the two initial central drops). Both environments
have since completed their 14-source central-only cutovers; see the
[final rollout status and retirement review](telemetry-rollout.md). Do not use
the pilot's old rollout lists, system paths or pending gates as current state.

Status **2026-09-25**. This is a `hel1` collector plus `backup1-staging`
source pilot, **not** a completed fleet migration. All 15 operator-enrolled
machine IDs are present in identical public manifests, but both rollout lists
select only `backup1-staging`. Other staging and production hosts still use
legacy logging; the staging backup dual-ships logs. No application dashboards
or alerts have been migrated. Verification used public metadata and aggregate
telemetry; administrative and machine credentials were not read into the
assistant session. Services consumed their own runtime credentials.

## Verified baseline

- Public DNS, checked through resolver `1.1.1.1`, resolves
  `telemetry.banditlair.com` to Pangolin; private TLS certificate validated.
  `hel1` current **and saved**
  system: `/nix/store/w2k2lvp84n236p030k8f2ay7q7khqwl8-nixos-system-hel1-26.05.20260820.5880666`.
  `bastion1-staging` current **and saved**:
  `/nix/store/430hhg4sbph9xbbb5s750ivbhhjq3267-nixos-system-bastion1-staging-25.11.20260404.36a6011`.
  `backup1-staging` current:
  `/nix/store/6ip1xwfvcgq10s2cz0zyb0v4px4j2l69-nixos-system-backup1-staging-25.11.20260404.36a6011`;
  saved D-R wrapper:
  `/nix/store/9d97rbgi4zrm7dbanmprfw1krgzkb0kl-activatable-nixos-system-backup1-staging-25.11.20260404.36a6011`.
  All three current/saved pairs were verified after deployment.
- Prometheus runtime retention 180 days; Loki runtime retention and maximum
  query lookback one year, compactor enabled. Loki HTTP and gRPC bind loopback;
  `frontend.address = "127.0.0.1"` is essential to keep scheduler callbacks off
  the unreachable container IP. All six Prometheus targets were healthy:
  DMARC, Loki, local node, backup node, Prometheus self and Synapse.
  Central and legacy LogQL count queries both succeeded.
- Backup machine's private HTTPS reached the ingest-only vhost with valid TLS:
  GET push returned 405, query returned 404; authorized Alloy POST returned
  204 from both destinations. The observed diagnostic VIP was
  `100.96.128.33`: resolve dynamically; **never pin it in permanent config**.
  An unrelated workstation client, despite being able to SSH to `hel1` through
  Pangolin, could not open TCP to the private HTTPS VIP. Its effective ingest
  grants were 0 versus the backup machine's 1 (its client ID is 10).
  This supports private ACL isolation, not public ingestion.
- With tunnels stopped, public fallback tested as the Alloy UID incremented
  the nft reject counter; the guard remained active. Machine clients on both
  ends reported registered/connected, direct peer, no relay. Source snapshot:
  native Alloy ~122 MiB and Olm ~18 MiB. Existing full/differential backup
  success and timers were unchanged.

## Failure modes already exercised

- Unselected hosts must have **no** Alloy etc file without a source and **no**
  phantom Promtail service: `mkIf` wraps the *whole* etc Alloy file and
  Promtail unit. Regression checks were added. A local Loki VM push/query
  failed before explicitly setting `frontend.address` to loopback and passed
  afterward when gRPC bound loopback.
- The initial short three-retry policy lost two new central log entries during
  a Loki restart; both remained in legacy logging. Both writers now use
  500 ms minimum, 5 min maximum and 10 retries. In a deterministic VM test
  against 12 seconds of HTTP 503, the first Alloy batch failed with 3 retries
  and passed with 10. These are **bounded retries, not a durable spool**.
- A scheduled PID 1 stop of the backup client for 20 seconds recovered; Alloy
  retained PID 2579390, backups stayed active. Marker
  `telemetry-pilot-private-tunnel-recovery-20260925-01` appeared **exactly once**
  in central and legacy logs; central drops remained at 2 old drops, legacy at
  0, with no additional drops. During a scheduled 75-second `hel1` client stop,
  the target went down then up (0 → 1) and local services stayed active.
  Neither test proves lossless delivery under arbitrary or prolonged outages.

## Pangolin 1.22.2 first-apply cache gap

On first apply, direct machine/resource cache grants existed and `siteNetworks`
mappings were correct, but site cache grants/links and private DNS aliases were
absent. Upstream cross-resource asynchronous rebuild can publish a stale
snapshot that removes first-new-machine site grants. The operational repair was
to reapply the **unchanged** blueprint via one fresh Newt process per affected
site, one site at a time, detached with `systemd-run` because SSH depends on
Newt; after settling, site grants, links and aliases were confirmed. No SQL
writes, broader grants or new credentials were used. This is a workaround,
**not** an upstream race fix: use it only after checking intended grants and
site health and observing the no-peer/no-alias case. Do not repeat blindly or
loosen the Personal role. For a new first-grant site, gate readiness on node up
and logs; if the verified cache gap persists, consider one unchanged reapply
and verify again before further rollout.

## Next gates (as recorded at pilot time; subsequently completed)

1. Preserve current pilot logs, metrics, private ACLs and existing backup timers.
   Expand both rollout lists
   together only after each new staging source's tunnel, node up, aliases,
   private TLS, ingest/query and legacy coexistence are checked. Do not assume
   the cache workaround is automatically required.
2. On staging backends separately validate the metrics-only proxy on port
   `30091` **and** the nginx Alloy branch; neither was covered by this backup
   pilot. Port dashboards and alerts with environment/canonical-host joins,
   checking UID collisions; establish an independent deadman outside `hel1`.
3. Only then consider production. Preserve each environment's old metrics VMs
   and history for up to 60 days **after that environment's actual cutover**;
   neither cutover clock has started. Do not claim full migration until
   application dashboards, alerting and source-by-source validation finish.

Offline regression checks (not substitutes for live gates):

```sh
nix build .#checks.x86_64-linux.telemetry-client --no-link
nix build .#checks.x86_64-linux.telemetry-gateway --no-link
nix build .#checks.x86_64-linux.telemetry-loki --no-link
nix build .#checks.x86_64-linux.telemetry-central --no-link
nix build .#checks.x86_64-linux.telemetry-enrollment --no-link
```
