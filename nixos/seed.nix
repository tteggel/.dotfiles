{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: let
  seedBootstrap = pkgs.writeShellApplication {
    name = "seed-bootstrap";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ../scripts/seed-bootstrap.sh;
  };
in {
  imports = [ ./common.nix ];

  networking.hostName = "seed";

  programs.zsh.enable = lib.mkForce false;
  services.openssh.enable = lib.mkForce false;

  users.users.seed = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = [ seedBootstrap ];

  environment.etc."nixos".source = inputs.self;

  programs.bash.interactiveShellInit = ''
    if [ -t 1 ] && [ ! -f /var/lib/seed-bootstrap.done ] && [ -z "''${SEED_BOOTSTRAP_RAN:-}" ]; then
      export SEED_BOOTSTRAP_RAN=1
      seed-bootstrap || true
    fi
  '';
}
