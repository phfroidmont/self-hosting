{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../environment.nix
    ../hardware/hcloud.nix
    ../modules
  ];

  networking.firewall.interfaces."eth1".allowedTCPPorts = [
    config.services.prometheus.exporters.node.port
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQKmE04ZeXN65PTt5cc0YAgBeFukwhP39Ccq9ZxlCkovUMcm9q1Gqgb1tw0hfHCUYK9D6In/qLgNQ6h0Etnesi9HUncl6GC0EE89kNOANZVLuPir0V9Rm7zo55UUUM/qlZe1L7b19oO4qT5tIUlM1w4LfduZuyaag2RDpJxh4xBontftZnCS6O2OI4++/6OKLkn4qtsepxPWb9M6lY/sb6w75LqyUXyjxxArrQMHpE4RQHTCEJiK9t+z5xpfI4WfTnIRQaCw6LxZhE9Kh/pOSVbLU6c5VdBHfCOPk6xrB3TbuUvMpR0cRtn5q0nJQHGhL0A709UXR1fnPm7Xs4GTIf2LWXch6mcrjkTocz8qmKDuMxQzY76QXy6A+rvghhOxnrZTEhLKExZxNqag72MIeippPFNbyOJgke3htHy74b9WjM1vZJ9VRYnmhxpGz0af//GF6LZQy7gOxBasSOv5u5r//1Ow7FNf2K5xYPGYzWRIDx+abMa+JwOyPHdZ9bR+jmB5R9VohFECFLgjm+O5Ed1LJgRX/6vYlB+8gZeeflbZpYYsSY/EcpsUKgtOmIBJT1svdjVTDdplihdFUzWfjL+n2O30K7yniNz6dGbXhxfqOVlp9R6ZsEdbGTX0IGpG+0ZgkUkLrgROAH1xiOYNhpXuD3l6rNXLw4HP3Mqjp3Fw== root@hel1"
  ];

  custom = {
    services.openssh.enable = true;
    services.monitoring-exporters.enable = true;
  };

}
