{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [ ./common.nix ];

  nix.settings.trusted-users = [ "root" "thom" ];

  networking.hostName = "thixos";

  users.users = {
    thom = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
      linger = true;
    };
  };

  home-manager.users.thom = import ../home/home.nix;

  services.tailscale.enable = true;
}
