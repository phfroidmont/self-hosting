{ pkgs, sopsModule }:
let
  lib = pkgs.lib;
  instances = {
    a = 4010;
    b = 4011;
  };
  journal = ''
    account assets:bank  ; type:C
    account equity:opening  ; type:E
    commodity 1,000.00 EUR

    2026-01-01 Opening
        assets:bank  100.00 EUR
        equity:opening
  '';
  # Each instance's books stand in for its forge repository, owned by the instance like one it
  # pushes to. Git refuses a repository another user owns, so the test uses it as that user.
  books = name: "/srv/books-${name}.git";
  elsewhereGit = "git -c user.name=Elsewhere -c user.email=elsewhere@example.invalid";
in
pkgs.testers.runNixOSTest {
  name = "plainsight";

  nodes.machine = { pkgs, ... }: {
    # Backup and monitoring are off; their modules only declare what PlainSight adds to them.
    imports = [
      sopsModule
      ../modules/backup-job.nix
      ../modules/monit.nix
      ../modules/plainsight.nix
    ];

    virtualisation.memorySize = 3072;
    environment.systemPackages = with pkgs; [ git curl sqlite ];

    custom.services.plainsight.instances = lib.mapAttrs
      (name: port: {
        domain = "${name}.example.invalid";
        inherit port;
        books.url = books name;
        deployKeyFile = pkgs.writeText "test-deploy-key" "unused for local books";
        signingSecretFile = pkgs.writeText "test-signing-secret" "vm-test-only-signing-secret-32-bytes";
        maxHeap = "384m";
      })
      instances;

    systemd.services.plainsight-test-books = {
      description = "Create the test instances' books";
      before = map (name: "plainsight-${name}.service") (lib.attrNames instances);
      requiredBy = map (name: "plainsight-${name}.service") (lib.attrNames instances);
      path = [ pkgs.git ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        work="$(mktemp -d)"
        git -C "$work" init --quiet -b master
        printf '%s' ${lib.escapeShellArg journal} > "$work/all.journal"
        git -C "$work" add all.journal
        ${elsewhereGit} -C "$work" commit --quiet -m Books
      '' + lib.concatMapStrings
        (name: ''
          if [ ! -e ${books name} ]; then
            git clone --quiet --bare "$work" ${books name}
            chown -R plainsight-${name}:plainsight-${name} ${books name}
          fi
        '')
        (lib.attrNames instances);
    };
  };

  testScript = ''
    import shlex

    instances = ${builtins.toJSON instances}

    def as_instance(name, command):
        return f"runuser -u plainsight-{name} -- sh -c {shlex.quote(command)}"

    for name, port in instances.items():
        machine.wait_for_unit(f"plainsight-{name}.service")
        machine.succeed(f"curl --fail --silent http://127.0.0.1:{port}/_health/ready")
        machine.succeed(f"curl --fail --silent --output /dev/null http://127.0.0.1:{port}/digest")
        machine.succeed(f"test \"$(stat -c %U /nix/var/data/plainsight/{name}/pta)\" = plainsight-{name}")
        machine.succeed(f"test \"$(stat -c %a /nix/var/data/plainsight/{name})\" = 700")

    with subtest("books committed elsewhere are pulled"):
        machine.succeed(as_instance(
            "a",
            "work=$(mktemp -d)"
            " && ${elsewhereGit} clone --quiet ${books "a"} $work"
            " && echo '; noted elsewhere' >> $work/all.journal"
            " && ${elsewhereGit} -C $work commit --quiet -am Elsewhere"
            " && ${elsewhereGit} -C $work push --quiet origin master",
        ))
        machine.succeed("systemctl restart plainsight-a.service")
        machine.wait_until_succeeds(
            as_instance("a", "git -C /nix/var/data/plainsight/a/pta log -1 --format=%s | grep -x Elsewhere"),
            timeout=60,
        )
        machine.succeed(as_instance("b", "git -C /nix/var/data/plainsight/b/pta log -1 --format=%s | grep -x Books"))

    with subtest("databases are snapshotted for backups"):
        machine.succeed("systemctl start plainsight-a-snapshot.service")
        machine.succeed(
            "test \"$(sqlite3 -readonly /nix/var/data/plainsight/a/backup/sessions.sqlite 'PRAGMA quick_check;')\" = ok"
        )

    with subtest("a new release snapshots the databases before starting"):
        machine.succeed("echo /nix/store/previous-plainsight.jar > /nix/var/data/plainsight/b/release")
        machine.succeed("systemctl restart plainsight-b.service")
        machine.succeed("grep -x /nix/store/previous-plainsight.jar /nix/var/data/plainsight/b/upgrades/*/release")
        machine.succeed(
            "test \"$(sqlite3 -readonly /nix/var/data/plainsight/b/upgrades/*/sessions.sqlite 'PRAGMA quick_check;')\" = ok"
        )
        machine.succeed("curl --fail --silent http://127.0.0.1:4011/_health/ready")
  '';
}
