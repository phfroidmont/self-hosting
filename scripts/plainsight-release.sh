#!/usr/bin/env bash
# Builds PlainSight at its checked-out commit, adds the jar to the Nix store and pins it in
# packages/plainsight/release.json. Deploying hel1 then ships that jar to every instance.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$(cd -- "${1:-$repo_root/../plainsight}" && pwd)"

if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
  printf '%s\n' "PlainSight has uncommitted changes; release a commit." >&2
  exit 1
fi
revision="$(git -C "$source_dir" rev-parse HEAD)"

(cd -- "$source_dir" && nix develop --command mill app.assembly)
jar="$source_dir/out/app/assembly.dest/out.jar"

name="plainsight-$revision.jar"
path="$(nix store add --mode flat --name "$name" "$jar")"
hash="$(nix hash file --type sha256 --sri "$jar")"

printf '{\n  "revision": "%s",\n  "hash": "%s"\n}\n' "$revision" "$hash" \
  > "$repo_root/packages/plainsight/release.json"
printf 'Pinned %s\n' "$path"
