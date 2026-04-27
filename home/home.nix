{ config, pkgs, inputs, ... }: let
  bespoke-zellij = inputs.dim-unfocused.packages.x86_64-linux;
  zellij-main = bespoke-zellij.zellij;
  dim-unfocused-wasm = bespoke-zellij.dim-unfocused;
  expectedDotfiles = [
    ".ssh" ".cache" ".local" ".config/gcloud" ".config/gh" ".config/claude"
    ".claude" ".gemini" ".zsh_history" ".zoxide.db" ".zoxide.db.zo"
    ".sudo_as_admin_successful" ".init-gh-completed" ".zcompdump*"
    ".zsh_sessions" ".wget-hsts" "src"
  ];
in {
  home.username = "thom";
  home.homeDirectory = "/home/thom";
  home.stateVersion = "25.05"; # Match NixOS stateVersion

  home.packages = with pkgs; [
    wget gh jq eza bat fd ripgrep fzf zoxide delta lazygit difftastic
    zellij-main
    (google-cloud-sdk.withExtraComponents [
      google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    kubectl firebase-tools
    inputs.llm-agents.packages.x86_64-linux.claude-code
    inputs.llm-agents.packages.x86_64-linux.gemini-cli
    inputs.llm-agents.packages.x86_64-linux.codex
    micro
    (writeShellApplication {
      name = "open-browser";
      text = builtins.readFile ../scripts/open-browser.sh;
    })
    (writeShellApplication {
      name = "zed";
      text = builtins.readFile ../scripts/zed.sh;
    })
    starship
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
      name = "gcloud-reauth";
      runtimeInputs = [ 
        (google-cloud-sdk.withExtraComponents [
          google-cloud-sdk.components.gke-gcloud-auth-plugin
        ]) 
        firebase-tools
      ];
      text = builtins.readFile ../scripts/gcloud-reauth.sh;
    })
    (writeShellApplication {
      name = "gcloud-switch";
      runtimeInputs = [ (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ]) kubectl fzf ];
      text = builtins.readFile ../scripts/gcloud-switch.sh;
    })
    (writeShellApplication {
      name = "hygiene-inspection";
      runtimeInputs = [
        fd git gh
        (google-cloud-sdk.withExtraComponents [
          google-cloud-sdk.components.gke-gcloud-auth-plugin
        ])
        kubectl
      ];
      text = builtins.readFile ../scripts/hygiene-inspection.sh;
    })
    (writeShellApplication {
      name = "init-gh";
      runtimeInputs = [ gh ];
      text = builtins.readFile ../scripts/init-gh.sh;
    })
  ];

  xdg.configFile."hygiene-expected-dotfiles".text = builtins.concatStringsSep "
" expectedDotfiles + "
";
  xdg.configFile."starship.toml".source = ../config/starship.toml;
  xdg.configFile."zellij/config.kdl".source = ../config/zellij/config.kdl;
  xdg.configFile."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;
  xdg.configFile."zellij/plugins/dim-unfocused.wasm".source = "${dim-unfocused-wasm}/share/zellij/plugins/dim-unfocused.wasm";

  home.file.".claude/settings.json".source = ../config/claude/settings.json;
  home.file.".gemini/settings.json".source = ../config/gemini/settings.json;

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
      export BROWSER=open-browser
      export EDITOR=micro
      export USE_GKE_GCLOUD_AUTH_PLUGIN=True
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      init-gh
      eval "$(starship init zsh)"

      # Auto-attach to zellij session (or start one) unless already inside zellij
      if [ -z "$ZELLIJ" ]; then
        session-picker; exit
      fi
      eval "$(fzf --zsh)"
      eval "$(zoxide init zsh)"

      # Set pane title to repo:branch or cwd (picked up by Zellij)
      _set_pane_title() {
        local title
        local repo
        repo=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$repo" ]]; then
          local name branch dirty
          name=$(basename "$repo")
          branch=$(git branch --show-current 2>/dev/null)
          [[ -n $(git status --porcelain 2>/dev/null | head -1) ]] && dirty="*"
          title="''${name}:''${branch}''${dirty}"
        else
          title="''${PWD/#$HOME/~}"
        fi
        print -Pn "\e]2;''${title}\a"
      }
      precmd_functions+=(_set_pane_title)

      # Emacs mode (enables Ctrl+A/E/K/U/W/R/L, Alt+D/B/F, etc.)
      bindkey -e

      # Word navigation
      bindkey '\e[1;5D' backward-word          # Ctrl+Left
      bindkey '\e[1;5C' forward-word           # Ctrl+Right
      bindkey '\e[1;3D' backward-word          # Alt+Left
      bindkey '\e[1;3C' forward-word           # Alt+Right

      # Line navigation
      bindkey '\e[H'  beginning-of-line        # Home (normal mode)
      bindkey '\eOH'  beginning-of-line        # Home (application mode)
      bindkey '\e[F'  end-of-line              # End (normal mode)
      bindkey '\eOF'  end-of-line              # End (application mode)

      # Deletion
      bindkey '\e[3~'   delete-char            # Delete
      bindkey '\e[3;5~' kill-word              # Ctrl+Delete
      bindkey '\e^?'    backward-kill-word     # Alt+Backspace
      bindkey '\e^H'    backward-kill-word     # Ctrl+Backspace

      # History
      bindkey '\e[1;2A' up-line-or-history     # Shift+Up
      bindkey '\e[1;2B' down-line-or-history   # Shift+Down
      bindkey '\e[1;2D' backward-word          # Shift+Left
      bindkey '\e[1;2C' forward-word           # Shift+Right
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
      user.name = "Thom Leggett";
      user.email = "thom@tteggel.org";
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
