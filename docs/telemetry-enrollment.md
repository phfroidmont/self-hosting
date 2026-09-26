# Pangolin telemetry enrollment (operator runbook)

Enrollment creates client identities, **not** permission to deploy the fleet. As
of the completed rollout, all 15 machine IDs (the `hel1` collector and 14 Osteoview sources)
are enrolled; both public manifests are complete and identical. Both
`telemetry-rollout.nix` and
`/home/phfroidmont/Projects/froidmont.solutions/infrastructure/nix/telemetry-rollout.nix`
now authorize all 14 sources across staging and production. Both environments
completed central-only cutovers; see [final rollout status](telemetry-rollout.md).
Enrollment remains the operator bootstrap process for future expansion, not
proof that a new source is deployed.

The loopback Integration API is deployed on `pangolin1`: its health endpoint was
verified through an operator-style SSH Unix socket, protected routes reject
unauthenticated requests, and port 3003 is not reachable publicly. Public
DNS for `telemetry.banditlair.com` points to Pangolin; private TLS and the
selected source/central pilot were verified on 2026-09-25.

## Preconditions

1. An operator, not an agent, obtains a **temporary, scoped Pangolin API key**
   permitting `getOrg`, `listClients`, `getClient`, and `createClient`. Enter it
   only at the script's hidden controlling-TTY prompt in `id.secret` form; never
   supply it via argv, environment, a file, chat, or logs. Do not share decrypted
   SOPS leaves with an agent.
2. Deploy and verify the patched Pangolin package/control API first. Its private
   integration API must answer on gateway loopback `127.0.0.1:3003` via SSH;
   **do not** expose it through public Traefik or open a firewall port. An
   operator can check health without a key, after deployment:

   ```sh
   ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=yes root@pangolin.banditlair.com \
     'curl --fail --silent --show-error http://127.0.0.1:3003/v1/ >/dev/null'
   ```

   The enrollment script performs this health check over a private SSH Unix
   socket before requesting the key. It uses `-F /dev/null`, ignores SSH config,
   and requires a trusted `known_hosts` entry and an available default SSH
   identity or agent for `root@pangolin.banditlair.com`; there is no insecure
   host-key fallback. Confirm the host key independently before connecting.
3. Have both repositories at their expected paths and access to their public
   SOPS recipients. Run from this repository's `nix develop` shell (which imports
   `.asc` public GPG keys and supplies SOPS, jq, yq, SSH, curl and coreutils).
   The infrastructure `ci.public.key` is not imported by that hook; the operator
   must import it manually with `gpg --import` from the verified public-key bundle
   before `enroll`. `check` does **not** test local key availability: it returns
   after inventory and public SOPS metadata validation. For `enroll`, the
   operator must also be able to decrypt and encrypt **all three**
   destination files: `secrets.enc.yml` here and
   `environments/{staging,production}/secrets-{staging,production}.yaml` in the
   infrastructure repository. The script tests this before creating clients;
   do not grant an agent the operator's private key.
4. The verified organization ID is `banditlair`. Use the same ID for every run.
   DNS and private pilot TLS were separately verified; enrollment itself does
   not apply Terraform or validate a deployed certificate.

## Run

From `/home/phfroidmont/Projects/self-hosting`:
```sh
nix develop
./scripts/pangolin-enroll-telemetry.sh check --org banditlair \
  --infrastructure-repo /home/phfroidmont/Projects/froidmont.solutions/infrastructure
./scripts/pangolin-enroll-telemetry.sh enroll --org banditlair \
  --infrastructure-repo /home/phfroidmont/Projects/froidmont.solutions/infrastructure
```

`check` validates inventory and **public SOPS metadata**, not key availability:
it makes no API calls and does not decrypt real secrets. `enroll` prompts at the
TTY, uses the SSH socket to read the organization and client identities, and creates missing
ones. It verifies each identity before writing its SOPS leaf. A successful run
publishes identical **public, nonsecret** `telemetry-enrollment.json` manifests
at both repository roots, with verified IDs and utility network settings. It
prints `Enrollment complete` only after publishing both manifests. It stores
per-machine `{id,secret}` as a JSON string at
`telemetry/clients/<host>` in `secrets.enc.yml` for `hel1` or the matching
infrastructure `environments/<environment>/secrets-<environment>.yaml` for
sources. The script does not stage, commit, deploy, or grant additional machines.

## Interruption, review, and rollout

Encrypted recovery checkpoints default to
`~/.local/state/pangolin-enroll-telemetry` (owned, mode `0700`; checkpoint files
mode `0600`). They bind the absolute paths of both repositories, gateway, org,
and inventory identity before the create request. Keep these files and their
backups safe. Re-run `enroll` with the **same** arguments to resume; it verifies
existing identities rather than deleting or blindly retrying creation. A
`prepared` intent can proceed; an `attempted` create with no matching client is
ambiguous and blocks. **Never remove or edit attempted checkpoints to unblock
it.** Preserve/copy existing backups, inspect public IDs and read-only API
client records with the operator, then reconcile manually. A partially updated
set of SOPS files is possible after interruption, but the public manifest is
published only after all identities verify; do not enable rollout until it is
complete. An unrelated existing credential or conflicting manifest must be
reconciled, not overwritten.

Review the public manifest and inventory diff without exposing the API key or
decrypted leaves; the agent may inspect nonsecret files. Keep both rollout lists
in sync; the existing 14 sources are already included. For future machines,
validate the source's actual private interface and CIDR, intended roles and
effective grants, node/nginx/application targets as applicable, TLS, ingestion
and legacy coexistence before cutover; the
[pilot record](telemetry-pilot.md) explains the first-grant cache gap, not a
pending gate for the existing fleet. Enrollment alone is not evidence of a
deployed source. Revoke the
temporary bootstrap API key in the Pangolin UI once enrollment is complete;
retain encrypted checkpoints until new systems are validated and backed up.
Future machines require an inventory update and a fresh scoped enrollment key;
run enrollment again, then explicitly expand both rollout lists only after
validation.

Offline verification (no live API or secret material):

```sh
bash -n scripts/pangolin-enroll-telemetry.sh
nix build .#checks.x86_64-linux.telemetry-enrollment --no-link
```
