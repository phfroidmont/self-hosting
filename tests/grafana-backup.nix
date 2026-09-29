{ pkgs, helConfiguration }:
let
  cfg = helConfiguration.config.custom.services.backup-job;
  liveDir = "/nix/var/data/grafana/data";
  snapshotPath = "nix/var/data/backup/grafana.sqlite";
in
assert builtins.elem "- ${liveDir}/grafana.db" cfg.patterns;
assert builtins.elem "- ${liveDir}/grafana.db-wal" cfg.patterns;
assert builtins.elem "- ${liveDir}/grafana.db-shm" cfg.patterns;
assert builtins.elem "- ${liveDir}/grafana.db-journal" cfg.patterns;
assert builtins.elem "- ${liveDir}/log" cfg.patterns;
assert builtins.elem snapshotPath cfg.restoreTestPaths;
assert builtins.elem "nix/var/data/murmur/murmur.sqlite" cfg.restoreTestPaths;
pkgs.runCommand "grafana-backup-test"
{
  nativeBuildInputs = with pkgs; [ python3 sqlite borgbackup ];
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  python3 ${./grafana-backup.py} \
    ${pkgs.callPackage ../packages/grafana-backup { }}/bin/grafana-backup \
    ${pkgs.writeText "grafana-backup-patterns" (pkgs.lib.concatStringsSep "\n" cfg.patterns)} \
    ${pkgs.writeShellScript "grafana-restore-check" ("set -euo pipefail\n" + cfg.restoreTestScript)}
  touch "$out"
''
