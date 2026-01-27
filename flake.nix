{
  description = "Thomnix WSL2";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-wsl,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    nixosConfigurations = {
      thixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          ./nixos/configuration.nix
          {
            system.stateVersion = "25.05";
            wsl.enable = true;
            wsl.defaultUser = "thom";
          }
        ];
      };
    };
  };
}
