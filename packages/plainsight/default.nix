{ requireFile }:
let
  release = builtins.fromJSON (builtins.readFile ./release.json);
in
# The jar is built from a PlainSight commit outside Nix and pinned by hash in release.json.
requireFile {
  name = "plainsight-${release.revision}.jar";
  inherit (release) hash;
  message = ''
    The PlainSight ${release.revision} jar is not in the Nix store.
    Build and add it from a clean PlainSight checkout of that commit:

      scripts/plainsight-release.sh ../plainsight
  '';
}
