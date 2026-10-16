{ pkgs, helConfiguration }:
let
  config = helConfiguration.config;
  cfg = config.custom.services.backup-job;
  borg = pkgs.callPackage ../packages/borg-churn-tolerant {
    borgbackup = config.services.borgbackup.package;
  };
  fakeBorg = exitStatus: pkgs.callPackage ../packages/borg-churn-tolerant {
    borgbackup = pkgs.writeShellScriptBin "borg" "exit ${toString exitStatus}";
  };
  jobPath = config.systemd.services.borgbackup-job-data.path;
in
assert builtins.head jobPath == borg;
assert builtins.elem "! /nix/var/data/reticulum/rns/storage/ratchets" cfg.patterns;
assert builtins.elem "! /nix/var/data/reticulum/rns/storage/resources" cfg.patterns;
assert builtins.elem "! /nix/var/data/plainsight/ph/data/*.sqlite*" cfg.patterns;
pkgs.runCommand "borg-churn-tolerant-test" { } ''
  set -euo pipefail
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME" data
  echo kept > data/kept
  echo secret > data/unreadable
  chmod 000 data/unreadable

  expect() {
    expected="$1"
    shift
    status=0
    "$@" 2> stderr || status=$?
    if [ "$status" -ne "$expected" ]; then
      cat stderr
      echo "expected exit status $expected, got $status: $*"
      exit 1
    fi
  }

  ${borg}/bin/borg init --encryption=none repo

  # A vanished file (107) is accepted and the archive keeps the rest.
  expect 0 ${borg}/bin/borg create repo::vanished data/kept data/vanished
  grep -q "accepting the archive" stderr
  ${borg}/bin/borg list --short repo::vanished | grep -qx data/kept

  # A changed file (100) is accepted too.
  expect 0 ${fakeBorg 100}/bin/borg create repo::changed data

  # Any other warning still fails, alone or mixed with a vanished file.
  expect 105 ${borg}/bin/borg create repo::unreadable data/kept data/unreadable
  expect 1 ${borg}/bin/borg create repo::mixed data/kept data/unreadable data/vanished
  expect 1 ${fakeBorg 1}/bin/borg create repo::generic data
  expect 101 ${fakeBorg 101}/bin/borg create repo::pattern data

  # Only `borg create` warnings are accepted.
  expect 107 ${fakeBorg 107}/bin/borg extract repo::vanished

  touch "$out"
''
