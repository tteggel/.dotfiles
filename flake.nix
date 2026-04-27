{
  description = "Thomnix WSL2";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    dim-unfocused.url = "path:./bespoke/zellij/dim-unfocused";
  };

  outputs = {
    self,
    nixpkgs,
    nixos-wsl,
    home-manager,
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
          home-manager.nixosModules.home-manager
          ./nixos/configuration.nix
          {
            system.stateVersion = "25.05";
            wsl.enable = true;
            wsl.defaultUser = "thom";
            wsl.interop.register = true;
          }
        ];
      };
    };
    homeConfigurations = {
      "thom@nix" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = { inherit inputs outputs; };
        modules = [ ./home/home.nix ];
      };
    };
  };
}
