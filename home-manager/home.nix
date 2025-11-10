{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
  ];

  nixpkgs = {
    overlays = [
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  home = {
    username = "thom";
    homeDirectory = "/home/thom";
  };

  home.packages = with pkgs; [ 
    steam 
  ];

  programs.home-manager.enable = true;
  programs.git = {
    enable = true;
    settings.user.name = "Thom Leggett";
    settings.user.email = "thom@tteggel.org";
  };

  systemd.user.startServices = "sd-switch";

  home.stateVersion = "25.05";
}
