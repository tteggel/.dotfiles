{ config, pkgs, inputs, lib, ... }: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  bespoke-zellij = inputs.dim-unfocused.packages.x86_64-linux;
  zellij-main = bespoke-zellij.zellij;
  dim-unfocused-wasm = bespoke-zellij.dim-unfocused;
  llm-agents = inputs.llm-agents.packages.x86_64-linux;
  mcp = import ./mcp.nix { inherit pkgs lib; };
  codex-cfg = import ./codex.nix { inherit lib; };
  grok-cfg = import ./grok.nix { inherit pkgs; inherit (mcp) servers; };
  claude = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [ llm-agents.claude-code ];
    # `=` form is required: --mcp-config is variadic and would otherwise consume
    # subsequent positional args as additional config files.
    text = ''exec claude --mcp-config=${mcp.claudeMcpConfig} "$@"'';
  };
  codex = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [ llm-agents.codex ];
    text = ''exec codex ${lib.concatStringsSep " " (mcp.codexArgs ++ codex-cfg.tuiArgs)} "$@"'';
  };
  agy = llm-agents.antigravity-cli;
  grok = llm-agents.grok;
  open-browser = pkgs.writeShellApplication {
    name = "open-browser";
    text = builtins.readFile ../scripts/open-browser.sh;
  };
  # Tools that exec `xdg-open` directly (ignoring $BROWSER) get a working one.
  # runtimeInputs pins open-browser by store path, so this does not depend on
  # the user profile being on PATH.
  xdg-open = pkgs.writeShellApplication {
    name = "xdg-open";
    runtimeInputs = [ open-browser ];
    text = builtins.readFile ../scripts/xdg-open.sh;
  };
  expectedDotfiles = [
    ".cache" ".local" ".zsh_history" ".zoxide.db" ".zoxide.db.zo"
    ".zcompdump*" ".zsh_sessions" "src"
    ".nix-profile" ".nix-defexpr" ".nix-channels"
    ".bashrc" ".bash_logout" ".bash_history" ".profile"
  ];
in {
  imports = [ ./shell.nix ./skills.nix ];

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
    lazygit yazi nodejs
    zellij-main
    claude
    agy
    codex
    grok
    # From llm-agents rather than nixpkgs: the CLI moves fast and llm-agents
    # tracks it closely (0.10.0 vs nixpkgs' 0.9.0), same as the agent CLIs.
    llm-agents.entire
    open-browser
    xdg-open
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
      name = "claude-statusline";
      runtimeInputs = [ jq git ];
      text = builtins.readFile ../scripts/claude-statusline.sh;
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
      name = "keybinds-help";
      text = builtins.readFile ../scripts/keybinds-help.sh;
    })
  ];

  xdg.configFile."hygiene-expected-dotfiles".text = builtins.concatStringsSep "\n" expectedDotfiles + "\n";
  xdg.configFile."starship.toml".source = ../config/starship.toml;
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;
  xdg.configFile."zellij/config.kdl".source = ../config/zellij/config.kdl;
  xdg.configFile."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;
  xdg.configFile."zellij/plugins/dim-unfocused.wasm".source = "${dim-unfocused-wasm}/share/zellij/plugins/dim-unfocused.wasm";

  home.file = mcp.agyExtensionFiles // grok-cfg.managedFiles // {
    ".claude/settings.json".source = ../config/claude/settings.json;
  };

  home.activation.agyPluginImport = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${agy}/bin/agy plugin import gemini >/dev/null || true
  '';

  home.activation.agySettingsSeed = lib.hm.dag.entryAfter ["writeBoundary"] ''
    settings="$HOME/.gemini/antigravity-cli/settings.json"
    if [ ! -e "$settings" ]; then
      install -d "$(dirname "$settings")"
      install -m 0644 ${pkgs.writeText "agy-settings.json" (builtins.toJSON {
        enableTelemetry = false;
        chromiumSandbox = true;
      })} "$settings"
    fi
  '';

  programs.zsh = {
    initContent = ''
      setopt HIST_FCNTL_LOCK
      setopt HIST_IGNORE_DUPS
      setopt HIST_IGNORE_SPACE
      setopt SHARE_HISTORY

      export STARSHIP_CONFIG=~/.config/starship.toml
      export ZELLIJ_CONFIG_DIR=~/.config/zellij
      export COLORTERM=truecolor
      export CLAUDE_CODE_EFFORT_LEVEL=max
      export EDITOR=micro
      export BROWSER=open-browser
      # `entire login` defaults to the OS keyring via the D-Bus Secret Service.
      # WSL has a session bus but nothing provides org.freedesktop.secrets, so
      # the token write fails ("The name is not activatable") and the login is
      # thrown away. Persist to ~/.config/entire/tokens.json (0600) instead.
      export ENTIRE_TOKEN_STORE=file
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
  };

  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "YOLO Agent";
      user.email = "agent@yolo.local";
      core.fsync = "committed";
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
