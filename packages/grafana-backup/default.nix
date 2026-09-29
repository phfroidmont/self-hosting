{ writeShellApplication, sqlite, coreutils }:
writeShellApplication {
  name = "grafana-backup";
  runtimeInputs = [ sqlite coreutils ];
  text = builtins.readFile ./snapshot.sh;
}
