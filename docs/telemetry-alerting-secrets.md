# Prepare telemetry alerting secrets (operator only)

This prepares an encrypted alert bundle and a public readiness marker; it does
**not** configure or deploy Grafana, Monit, SMTP, or an external deadman. Do not
give an assistant SMTP, administrator, machine, or GPG private credentials. Run
the commands locally with your own SOPS decryption identity. No upstream account
or API key is created. The original infrastructure ciphertexts stay unchanged.

From the self-hosting repository, enter `nix develop` and ensure the three
**public** recipient keys (admin, hel1, relay1) are available to GPG. The dev
shell's public-key import hook may not import these automatically; import only
the corresponding public `.asc` exports if needed. Decryption of the source
files requires an operator-held private key, but never a CI public key. The
dev shell includes Python 3 for the helper.

```sh
nix develop
bash scripts/prepare-telemetry-alerts.sh check --infrastructure-repo /home/phfroidmont/Projects/froidmont.solutions/infrastructure
bash scripts/prepare-telemetry-alerts.sh prepare --infrastructure-repo /home/phfroidmont/Projects/froidmont.solutions/infrastructure
```

`check` verifies only public keys and the existence of input ciphertexts; it
does not decrypt. `prepare` verifies the source SOPS MACs, takes production's
SMTP identity/password for the central sender, retains both staging and
production contact-point recipients, generates a fresh 32-byte hex watchdog
token inside the local process, and encrypts `secrets/telemetry-alerts.enc.yml`.
Recipient lists accept comma, semicolon, or newline separators and optional
display names. Mailboxes must have a dotted domain; percent-tagged addresses,
control characters, and SMTP passwords containing `"` or `\` are rejected
rather than embedded in an unsafe Monit string. The ciphertext must have
exactly the admin, hel1, and relay1 public recipients, with no extra recipients.
Only after ciphertext is durable does it publish
`telemetry-alerting.json` as `{"schemaVersion":1,"prepared":true}`. Failed
preparation leaves the initial `{}` marker unchanged. Existing ciphertext is
validated quietly and never replaced or rotated on a normal rerun; an
interrupted run with ciphertext but `{}` marker can be resumed. Stop and
investigate validation failures; do not delete the bundle merely to rerun.

Do not print or paste decrypted data, use shell tracing, or stage plaintext.
After local preparation, explicitly review the encrypted file and public marker,
then `git add -N secrets/telemetry-alerts.enc.yml` before any flake evaluation:
Nix does not see untracked files. This helper does not stage, commit, deploy, or
contact any service. Offline synthetic regression test:
`bash tests/prepare-telemetry-alerts-test.sh` (the synthetic fixture also checks
the generated Monit syntax when `monit` is on `PATH`).
