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
      experimental-features = "nix-command flakes";
      flake-registry = "";
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
    };
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  environment.systemPackages = with pkgs; [
    wget
    gh
    jq
    inputs.llm-agents.packages.x86_64-linux.claude-code
    inputs.llm-agents.packages.x86_64-linux.gemini-cli
    inputs.llm-agents.packages.x86_64-linux.codex
    starship
    (writeShellApplication {
      name = "init-gh";
      runtimeInputs = [ gh ];
      text = ''
        ppid=$(ps -p $$ -o ppid= | tr -d "[:space:]")
        pppid=$(ps -p "$ppid" -o ppid= | tr -d "[:space:]")
        pppbin=$(ps -p "$pppid" -o cmd= | tr -d "[:space:]")
        if [ "$pppbin" = '/bin/login-f' ]; then
          exit 1
        fi

        if ! mkdir "$HOME/.init-gh-completed" 2>/dev/null; then
          exit 0
        fi

        gh auth login --clipboard --git-protocol ssh --hostname github.com --web

        mkdir -p "$HOME/src/github.com/tteggel"
        gh repo clone tteggel/.dotfiles "$HOME/src/github.com/tteggel/.dotfiles"
      '';
    })
  ];

  environment.etc."starship.toml".source = ../config/starship.toml;

  networking.hostName = "thixos";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    interactiveShellInit = ''
      init-gh
      eval "$(starship init zsh)"
      export STARSHIP_CONFIG=/etc/starship.toml

      # Shift+arrow key bindings (Windows Terminal)
      bindkey '\e[1;2D' backward-word
      bindkey '\e[1;2C' forward-word
      bindkey '\e[1;2A' up-line-or-history
      bindkey '\e[1;2B' down-line-or-history
    '';
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    config = {
      user.name = "Thom Leggett";
      user.email = "thom@tteggel.org";
    };
  };

  programs.nix-ld.enable = true;

  users.users = {
    thom = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.tailscale.enable = true;
}
