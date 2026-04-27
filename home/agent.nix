{ config, pkgs, inputs, lib, ... }: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  bespoke-zellij = inputs.dim-unfocused.packages.x86_64-linux;
  zellij-main = bespoke-zellij.zellij;
  dim-unfocused-wasm = bespoke-zellij.dim-unfocused;
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
    lazygit yazi
    zellij-main
    inputs.llm-agents.packages.x86_64-linux.claude-code
    inputs.llm-agents.packages.x86_64-linux.gemini-cli
    inputs.llm-agents.packages.x86_64-linux.codex
    (writeShellApplication {
      name = "open-browser";
      text = builtins.readFile ../scripts/open-browser.sh;
    })
    (writeShellApplication {
      name = "zed";
      text = builtins.readFile ../scripts/zed.sh;
    })
    (writeShellApplication {
      name = "init-yolo";
      runtimeInputs = [ gh ];
      text = builtins.readFile ../scripts/init-yolo.sh;
    })
    (writeShellApplication {
      name = "session-picker";
      runtimeInputs = [ zellij-main fzf zoxide gh git ];
      text = builtins.readFile ../scripts/session-picker.sh;
    })
    (writeShellApplication {
      name = "claude-session";
      runtimeInputs = [ fzf inputs.llm-agents.packages.x86_64-linux.claude-code ];
      text = builtins.readFile ../scripts/claude-session.sh;
    })
    (writeShellApplication {
      name = "gemini-session";
      runtimeInputs = [ fzf inputs.llm-agents.packages.x86_64-linux.gemini-cli ];
      text = builtins.readFile ../scripts/gemini-session.sh;
    })
    (writeShellApplication {
      name = "code-session";
      runtimeInputs = [ zellij-main ];
      text = builtins.readFile ../scripts/code-session.sh;
    })
    (writeShellApplication {
      name = "command-palette";
      runtimeInputs = [ fzf zellij-main fd zoxide ];
      text = builtins.readFile ../scripts/command-palette.sh;
    })
    (writeShellApplication {
      name = "url-picker";
      runtimeInputs = [ fzf zellij-main ];
      text = builtins.readFile ../scripts/url-picker.sh;
    })
    (writeShellApplication {
      name = "osc52-copy";
      text = builtins.readFile ../scripts/osc52-copy.sh;
    })
  ];

  xdg.configFile."hygiene-expected-dotfiles".text = builtins.concatStringsSep "\n" expectedDotfiles + "\n";
  xdg.configFile."starship.toml".source = ../config/starship.toml;
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;
  xdg.configFile."zellij/config.kdl".source = ../config/zellij/config.kdl;
  xdg.configFile."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;
  xdg.configFile."zellij/plugins/dim-unfocused.wasm".source = "${dim-unfocused-wasm}/share/zellij/plugins/dim-unfocused.wasm";

  programs.bash = {
    enable = true;
    initExtra = ''
      # Auto-launch zsh for interactive sessions
      if [ -t 1 ] && [ -n "$BASH_VERSION" ] && [ "$0" = "-bash" -o "$0" = "bash" ]; then
        exec zsh -l
      fi
    '';
  };

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
      export ZELLIJ_CONFIG_DIR=~/.config/zellij
      export CLAUDE_CODE_EFFORT_LEVEL=max
      export EDITOR=micro
      export BROWSER=open-browser
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      
      init-yolo

      if [ -f "$HOME/.config/github-token.env" ]; then
        source "$HOME/.config/github-token.env"
      fi

      if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "\033[0;33mWarning: GITHUB_TOKEN is not set. Git auth will fail.\033[0m"
      fi

      eval "$(starship init zsh)"

      # Auto-attach to zellij session (or start one) unless already inside zellij
      if [ -z "$ZELLIJ" ]; then
        session-picker; exit
      fi
      eval "$(fzf --zsh)"
      eval "$(zoxide init zsh)"

      # Yazi wrapper for cwd syncing
      function yy() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }

      echo -e "\033[1;31m"
      echo "             _       _               "
      echo " _   _  ___ | | ___ (_)_  _____  ___ "
      echo "| | | |/ _ \\| |/ _ \\| \\ \\/ / _ \\/ __|"
      echo "| |_| | (_) | | (_) | |>  < (_) \\__ \\"
      echo " \__, |\___/|_|\___/|_/_/\\_\___/|___/"
      echo " |___/                               "
      echo -e "\033[0m"
      
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
