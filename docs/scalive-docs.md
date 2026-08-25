# Scalive Documentation

The public documentation application runs on `hel1` behind Nginx at
`https://scalive.dev`. It is a JVM LiveView service rather than a static site.

## Release Flow

The Scalive `master` workflow builds and smoke-tests one executable JAR. A
separate deployment job downloads that artifact on a fresh runner and streams
it to the restricted `scalive-docs-deploy` SSH account.

The SSH key can only invoke the forced deployment command. Uploads are bounded,
checksummed, and limited to one pending release. Activation promotes a
root-owned release, restarts the sandboxed service, and requires `/health` to
return the exact embedded Git revision. A failed activation restores and
revalidates the previous release. GitHub run IDs are recorded as monotonic
deployment generations so rerunning an older workflow cannot downgrade the
site.

## Bootstrap

1. Apply `terraform/dns.tf` so the apex A and AAAA records and the `www` CNAME
   resolve to `hel1`.
2. Deploy the `hel1` NixOS configuration. The service remains inactive until a
   first release exists, while Nginx and ACME can initialize.
3. Create a GitHub environment named `production` in `phfroidmont/scalive`,
   restrict it to `master`, and add `SCALIVE_DOCS_DEPLOY_KEY` with the private
   half of the public key configured in `profiles/hel.nix`.
4. Run the Scalive `Publish snapshot` workflow on `master`.

The application signing secret is stored at `scalive/docs/token_secret` in
`secrets.enc.yml` and is delivered only through a systemd credential.

## Verification

```bash
curl --fail --silent --show-error https://scalive.dev/health
curl --fail --silent --show-error --location https://www.scalive.dev/health
systemctl status scalive-docs.service
journalctl --unit scalive-docs.service
```

The health response is the full 40-character Git revision. Check both IPv4 and
IPv6 after DNS propagation, and verify a real `/live/websocket` connection from
a browser.

## Emergency Rollback

Automatic rollback covers failed startup and health checks. For an operator
rollback, select a retained directory under `/var/lib/scalive-docs/releases`,
atomically replace `/var/lib/scalive-docs/current` with a symlink to it, restart
`scalive-docs.service`, and verify that `/health` returns that directory name.
The next successful pipeline deployment replaces the rollback normally.
