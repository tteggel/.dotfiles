{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [ ./common.nix ./embedded.nix ./wslg.nix ];

  nix.settings.trusted-users = [ "root" "thom" ];

  networking.hostName = "thixos";

  # BookCreator's local dev apps must run on these origins (CORS), but public
  # DNS points them at Fastly. Node dev servers bind IPv4 through the preload
  # in home/shell.nix, so 127.0.0.1 is what answers. ::1 stays for servers that
  # still listen on [::], which the shared localhost refuses over 127.0.0.1
  # (see common.nix): clients try 127.0.0.1 first, then fall back to ::1.
  networking.hosts = let
    names = [
      "app-local.dev.bookcreator.com"
      "admin-local.dev.bookcreator.com"
      "read-local.dev.bookcreator.com"
      "missioncontrol-local.dev.bookcreator.com"
      "diagnostics-local.dev.bookcreator.com"
    ];
  in {
    "127.0.0.1" = names;
    "::1" = names;
  };

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
