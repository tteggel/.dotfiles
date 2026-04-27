{ config, pkgs, inputs, lib, ... }: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  expectedDotfiles = [
    ".cache" ".local" ".zsh_history" ".zoxide.db" ".zoxide.db.zo"
    ".zcompdump*" ".zsh_sessions" "src"
    ".nix-profile" ".nix-defexpr" ".nix-channels"
    ".bashrc" ".bash_logout" ".bash_history" ".profile"
  ];
in {
  home.stateVersion = "25.05";

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = "nix-command flakes";
      flake-registry = "";
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
    };
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  home.packages = with pkgs; [
    wget gh jq eza bat fd ripgrep fzf zoxide delta difftastic micro starship
    (writeShellApplication {
      name = "init-yolo";
      runtimeInputs = [ gh ];
      text = builtins.readFile ../scripts/init-yolo.sh;
    })
  ];

  xdg.configFile."hygiene-expected-dotfiles".text = builtins.concatStringsSep "\n" expectedDotfiles + "\n";
  xdg.configFile."starship.toml".source = ../config/starship.toml;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 10000;
    history.path = "$HOME/.zsh_history";
    initContent = ''
      setopt HIST_FCNTL_LOCK
      setopt HIST_IGNORE_DUPS
      setopt HIST_IGNORE_SPACE
      setopt SHARE_HISTORY

      export STARSHIP_CONFIG=~/.config/starship.toml
      export EDITOR=micro
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      
      init-yolo

      if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "\033[0;33mWarning: GITHUB_TOKEN is not set. Git auth will fail.\033[0m"
      fi

      eval "$(starship init zsh)"
      eval "$(fzf --zsh)"
      eval "$(zoxide init zsh)"
      
      # Auto-cd into the cloned repo if it's the only thing in src
      if [ "$PWD" = "$HOME" ] && [ -d "$HOME/src" ]; then
        repos=("$HOME/src"/*)
        if [ ''${#repos[@]} -eq 1 ] && [ -d "''${repos[0]}" ]; then
          cd "''${repos[0]}"
        fi
      fi
    '';
    shellAliases = {
      ls = "eza";
      ll = "eza -l --git";
      la = "eza -la --git";
      lt = "eza -T --git-ignore";
      cat = "bat --paging=never";
      grep = "rg";
      find = "fd";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "YOLO Agent";
      user.email = "agent@yolo.local";
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      difftool.difftastic.cmd = ''difft "$LOCAL" "$REMOTE"'';
      difftool.prompt = false;
      alias = {
        dft = "difftool -t difftastic";
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };
}
