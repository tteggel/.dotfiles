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

  # WSL's shared localhost (config/wslconfig) routes TCP/UDP for 127.0.0.1
  # through the Windows host, which loops it back only to ports bound for
  # IPv4: a dual-stack [::] listener (Node's listen() with no host, Go's
  # ":port") refuses 127.0.0.1, while ::1 never leaves Linux
  # (microsoft/WSL#14154). Stryker's worker log server dies on exactly this.
  # NixOS's own /etc/hosts maps localhost to ::1 as well (WSL's gives ::1 only
  # to ip6-localhost), so clients that try every address fall back to IPv6.
  wsl.wslConf.network.generateHosts = false;

  # ...with 127.0.0.1 still sorted ahead of ::1, so servers bound to
  # "localhost" (Vite, ng serve) keep taking IPv4: Windows reaches WSL over
  # 127.0.0.1 but hangs on ::1. Any precedence entry replaces glibc's whole
  # default table, so the rest restates it.
  networking.getaddrinfo.precedence = {
    "::ffff:127.0.0.0/104" = 60;
    "::1/128" = 50;
    "::/0" = 40;
    "2002::/16" = 30;
    "::/96" = 20;
    "::ffff:0:0/96" = 10;
  };
}
