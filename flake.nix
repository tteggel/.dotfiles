{
  description = "Thomnix WSL2";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    dim-unfocused.url = "path:./bespoke/zellij/dim-unfocused";

    # Agent skills (SKILL.md format, shared by Claude / Codex / Antigravity).
    # Add new GitHub-sourced skills here as `flake = false` inputs, then
    # reference them from `home/skills.nix`.
    code-review-skill = {
      url = "github:awesome-skills/code-review-skill";
      flake = false;
    };
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
      yoloixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          home-manager.nixosModules.home-manager
          ./nixos/yoloixos.nix
          {
            system.stateVersion = "25.05";
            wsl.enable = true;
            wsl.defaultUser = "agent";
          }
        ];
      };
      seed = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        system = "x86_64-linux";
        modules = [
          nixos-wsl.nixosModules.default
          home-manager.nixosModules.home-manager
          ./nixos/seed.nix
          {
            system.stateVersion = "25.05";
            wsl.enable = true;
            wsl.defaultUser = "seed";
            wsl.interop.register = true;
          }
        ];
      };
    };
    homeConfigurations = {
      "thom@nix" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        extraSpecialArgs = { inherit inputs outputs; };
        modules = [
          ./home/home.nix
          {
            home.username = builtins.getEnv "USER";
            home.homeDirectory = builtins.getEnv "HOME";
          }
        ];
      };
      "agent@nix" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        extraSpecialArgs = { inherit inputs outputs; };
        modules = [
          ./home/agent.nix
          {
            home.username = builtins.getEnv "USER";
            home.homeDirectory = builtins.getEnv "HOME";
          }
        ];
      };
    };
  };
}
