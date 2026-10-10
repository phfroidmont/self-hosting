# PlainSight

PlainSight instances run on `hel1`, one per set of books, each as a private
Pangolin HTTP resource like Grafana. Instance `ph` serves
`https://plainsight.banditlair.com` from loopback port 4010 to the `Personal`
role; Newt terminates HTTPS on `hel1`.

Each instance has its own system user `plainsight-<name>`, its own secrets under
`plainsight/<name>/` in `secrets.enc.yml`, and its own state in
`/nix/var/data/plainsight/<name>` (mode `0700`):

| Path | Contents |
| --- | --- |
| `pta/` | Clone of the books, pushed to and pulled from Forgejo with the deploy key |
| `data/` | Sessions, documents and connections: SQLite databases and the evidence archive |
| `backup/` | Consistent database snapshots taken before each Borg backup |
| `upgrades/` | Database snapshots taken before a new release first starts, the three newest |
| `release` | The jar the instance last started |

The module is [`modules/plainsight.nix`](../modules/plainsight.nix); instances,
secrets and the Newt resource are in [`profiles/hel.nix`](../profiles/hel.nix).

## Release flow

PlainSight is built outside Nix, as one jar, and pinned by hash:

```bash
scripts/plainsight-release.sh ../plainsight
git add packages/plainsight/release.json
git commit -m "chore(plainsight): release <short revision>"
deploy .#hel1
```

The script requires a clean PlainSight checkout, builds that commit with Mill,
adds the jar to the local Nix store and writes its revision and hash to
`packages/plainsight/release.json`. Building `hel1` needs that jar in the store;
deploy-rs copies it to `hel1` with the rest of the system.

Every instance runs the same jar, with Git, hledger, pdftotext and OpenSSH from
`hel1`'s nixpkgs. Starting an instance waits until `/_health/ready` answers, so a
release that does not start fails the activation and deploy-rs rolls back.

A release leaves Newt alone, so plain deploy-rs is safe. Adding or changing an
instance's Newt resource restarts Newt, which carries deploy-rs's own SSH
connection: activate those changes detached, with a host-local rollback timer,
as described in [Pangolin](pangolin.md#resource-naming).

## Bootstrap

1. Register the instance's deploy key in Forgejo, under the books repository's
   *Settings → Deploy keys*, with write access. Print its public half with:

   ```bash
   sops -d --extract '["plainsight"]["ph"]["deploy_key"]' secrets.enc.yml | ssh-keygen -y -f /dev/stdin
   ```

   An instance clones its books on its first start; without the key, that
   start fails and the deployment rolls back.
2. Apply `terraform/dns.tf`, so the domain resolves publicly to `pangolin1` for
   HTTP-01 certificates and the placeholder.
3. Add the domain to the workstation's explicit split-DNS match list (see
   [Pangolin](pangolin.md#https-and-dns)). Phones need the Pangolin client
   connected to reach it.
4. Deploy `hel1` detached, since its Newt resource is new (see above). Pangolin
   resolves the domain once Newt has registered the resource.

To bring existing data along, stop the instance, copy the `*.sqlite` databases
and `sessions/` of the old data directory into `data/` (not `.bak` files or
`plainsight.lock`), give them to the instance's user and start it again. Push
the old copy's unpushed books commits first: the sessions refer to them.

```bash
systemctl stop plainsight-ph
chown -R plainsight-ph:plainsight-ph /nix/var/data/plainsight/ph/data
systemctl start plainsight-ph
```

GoMining's bookmarklet holds the origin it was dragged from: drag it again from
the instance's Settings.

## Adding an instance

Add secrets `plainsight/<name>/{signing_secret,deploy_key,openai_api_key}`, an
entry under `custom.services.plainsight.instances` with its own port, domain and
books repository, its Newt private resource and its DNS record, then bootstrap it
as above. The OpenAI key is optional; without it the assistant is off. Further
settings, such as `PLAINSIGHT_AI_DAILY_ATTEMPT_LIMIT`, go in the instance's
`settings`.

## Verification

```bash
systemctl status plainsight-ph.service
journalctl --unit plainsight-ph.service
curl --fail http://127.0.0.1:4010/_health/ready
sudo -u plainsight-ph git -C /nix/var/data/plainsight/ph/pta status -sb
```

Settings → Books repository shows the last push or pull. In a browser, check the
Digest, an upload and the live connection through the private domain. Monit
checks each instance's health on loopback.

`nix build .#checks.x86_64-linux.plainsight` runs two instances in a VM: their
books are cloned, a commit pushed elsewhere is pulled, and both database
snapshots are taken.

### Deployment verification (2026-10-10)

Instance `ph` was activated detached with rollback armed, then persisted as
generation 215. It cloned `phfroidmont/pta` and is in step with it; Forgejo
accepted its deploy key for writing (`git push --dry-run`). Health returned
`200` on loopback and through `plainsight.banditlair.com` with a valid
certificate, and the LiveView connected in a browser through the private
domain. No unit failed. The first snapshot left stray `-wal`/`-shm` files beside
its copies; the fix, with `Type=exec`, went out by plain deploy-rs, which
restarted only PlainSight, and the next snapshot left just the three databases.

## Backups and rollback

Before each Borg backup, `plainsight-<name>-snapshot.service` copies the live
databases into `backup/` with SQLite's online backup and checks them; Borg skips
the live databases and `upgrades/`. A failed snapshot keeps the previous one
rather than stopping the other backups. The weekly restore test extracts each
instance's `backup/sessions.sqlite`. The books are in Forgejo, and `pta/` is
backed up too for commits not pushed yet.

A release migrates the databases when it first starts, and an older release
may not read them afterwards. Rolling back the system restores the previous jar,
not the databases: stop the instance, copy the databases from the snapshot in
`upgrades/` whose `release` names the jar now running back into `data/`, and
start it again.
