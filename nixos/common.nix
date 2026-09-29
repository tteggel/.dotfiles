{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  nixpkgs = {
    config = {
      allowUnfreePredicate = _: true;
    };
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      flake-registry = "";
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
    };
    channel.enable = false;

    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  programs.zsh.enable = true;
  programs.nix-ld.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs = { inherit inputs outputs; };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # WSL >= 2.9 mounts /proc/sys/fs/binfmt_misc/status read-only
  # (microsoft/WSL#40621) so a distro can't flush every handler. Run with no
  # arguments, systemd-binfmt begins with exactly that flush and exits 1 on
  # EROFS despite logging "ignoring", failing every nixos-rebuild switch (and
  # scripts/update-system.sh with it). Naming the rules file skips the flush
  # (rules are still replaced by name); --unregister hits the same wall, so
  # there's no ExecStop.
  systemd.services.systemd-binfmt = lib.mkIf (config.boot.binfmt.registrations != {}) {
    serviceConfig = {
      ExecStart = [ "" "${config.systemd.package}/lib/systemd/systemd-binfmt /etc/binfmt.d/nixos.conf" ];
      ExecStop = "";
    };
  };
}
