{ config, pkgs, inputs, lib, ... }: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  bespoke-zellij = inputs.dim-unfocused.packages.x86_64-linux;
  zellij-main = bespoke-zellij.zellij;
  dim-unfocused-wasm = bespoke-zellij.dim-unfocused;
  llm-agents = inputs.llm-agents.packages.x86_64-linux;
  mcp = import ./mcp.nix { inherit pkgs lib; };
  codex-cfg = import ./codex.nix { inherit lib; };
  grok-cfg = import ./grok.nix { inherit lib grok; inherit (mcp) servers; };
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
    text = ''exec codex ${lib.concatStringsSep " " (mcp.codexArgs ++ codex-cfg.configArgs)} "$@"'';
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
  googleCloudSdkWithGke = pkgs.google-cloud-sdk.withExtraComponents [
    pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
  ];
  expectedDotfiles = [
    ".ssh" ".cache" ".local" ".config" ".claude" ".gemini" ".grok"
    ".zsh_history" ".zoxide.db" ".zoxide.db.zo" ".sudo_as_admin_successful"
    ".init-gh-completed" ".zcompdump*" ".zsh_sessions" ".wget-hsts" "src"
    ".nix-profile" ".nix-defexpr" ".nix-channels"
    ".bashrc" ".bash_logout" ".bash_history" ".profile"
  ];
  isMinimal = builtins.getEnv "MINIMAL_ENV" != "";
in {
  imports = [ ./shell.nix ./skills.nix ];

  home.stateVersion = "25.05"; # Match NixOS stateVersion

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

  home.activation.windowsterminal = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Glob over user profiles (LocalState is created lazily on WT's first
    # launch, so gating on it would silently no-op on freshly-imaged Windows
    # boxes where the user opened wsl from cmd.exe before ever opening WT).
    for user_dir in /mnt/c/Users/*; do
      [ -f "$user_dir/NTUSER.DAT" ] || continue
      [ -w "$user_dir" ] || continue
      wt_dir="$user_dir/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
      mkdir -p "$wt_dir" || continue
      ${pkgs.gnused}/bin/sed 's/\x1b/\\u001b/g' ${../config/windows-terminal.json} \
        > "$wt_dir/settings.json"
    done
  '';

  home.activation.wslconfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    for user_dir in /mnt/c/Users/*; do
      [ -f "$user_dir/NTUSER.DAT" ] || continue
      [ -w "$user_dir" ] || continue
      install -m 0644 ${../config/wslconfig} "$user_dir/.wslconfig"
    done
  '';

  home.activation.chromeDevtoolsShortcut = lib.hm.dag.entryAfter ["writeBoundary"] ''
    powershell=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    [ -x "$powershell" ] || exit 0
    for user_dir in /mnt/c/Users/*; do
      [ -f "$user_dir/NTUSER.DAT" ] || continue
      [ -w "$user_dir" ] || continue
      install -d "$user_dir/AppData/Local/chrome-devtools-mcp"
      install -m 0644 ${../config/windows/install-chrome-devtools-shortcut.ps1} \
        "$user_dir/AppData/Local/chrome-devtools-mcp/install-shortcut.ps1"
      ps1_win=$(/sbin/wslpath -w "$user_dir/AppData/Local/chrome-devtools-mcp/install-shortcut.ps1")
      "$powershell" -NoProfile -ExecutionPolicy Bypass -File "$ps1_win" || true
    done
  '';

  # FancyZones lives on the Windows side (PowerToys). Same pattern as
  # windowsterminal: push the repo copy onto every writable Windows profile.
  # applied-layouts.json is keyed by GPU-specific monitor-instance IDs, so a
  # blind overwrite would miss displays on another machine. Stamp the default
  # custom grid onto every device the target already knows; fall back to a
  # straight copy when PowerToys has not created the file yet.
  home.activation.fancyzones = lib.hm.dag.entryAfter ["writeBoundary"] ''
    fancyzones_src=${../config/windows/fancyzones}
    jq=${pkgs.jq}/bin/jq
    for user_dir in /mnt/c/Users/*; do
      [ -f "$user_dir/NTUSER.DAT" ] || continue
      [ -w "$user_dir" ] || continue
      fz_dir="$user_dir/AppData/Local/Microsoft/PowerToys/FancyZones"
      mkdir -p "$fz_dir" || continue
      for f in settings.json custom-layouts.json default-layouts.json \
               layout-hotkeys.json layout-templates.json; do
        install -m 0644 "$fancyzones_src/$f" "$fz_dir/$f"
      done
      dest="$fz_dir/applied-layouts.json"
      src="$fancyzones_src/applied-layouts.json"
      if [ -f "$dest" ] && "$jq" -e '."applied-layouts" | type == "array"' "$dest" >/dev/null 2>&1; then
        "$jq" --slurpfile defaults "$fancyzones_src/default-layouts.json" '
          ($defaults[0]."default-layouts"[0].layout) as $layout
          | ."applied-layouts" |= map(. + {"applied-layout": $layout})
        ' "$dest" > "$dest.tmp" && mv "$dest.tmp" "$dest"
        chmod 0644 "$dest"
      else
        install -m 0644 "$src" "$dest"
      fi
      pt_settings="$user_dir/AppData/Local/Microsoft/PowerToys/settings.json"
      if [ -f "$pt_settings" ] && [ -w "$pt_settings" ]; then
        "$jq" '.enabled.FancyZones = true' "$pt_settings" > "$pt_settings.tmp" \
          && mv "$pt_settings.tmp" "$pt_settings"
        chmod 0644 "$pt_settings"
      fi
    done
  '';

  home.packages = with pkgs; [
    # gh is installed here rather than via `programs.gh.enable` because the
    # home-manager module manages ~/.config/gh/config.yml as a /nix/store
    # symlink, which then explodes with EROFS when `gh auth login` tries to
    # rewrite the file (e.g. to record git_protocol). Let gh own its config.
    gh
    wget jq eza bat fd ripgrep fzf zoxide delta lazygit yazi difftastic
    kubectl firebase-tools micro starship nodejs
    # From llm-agents rather than nixpkgs: the CLI moves fast and llm-agents
    # tracks it closely (0.10.0 vs nixpkgs' 0.9.0), same as the agent CLIs.
    llm-agents.entire
    googleCloudSdkWithGke
    open-browser
    xdg-open
    (writeShellApplication {
      name = "zed";
      text = builtins.readFile ../scripts/zed.sh;
    })
    (writeShellApplication {
      name = "gcloud-reauth";
      runtimeInputs = [ 
        googleCloudSdkWithGke
        firebase-tools
      ];
      text = builtins.readFile ../scripts/gcloud-reauth.sh;
    })
    (writeShellApplication {
      name = "gcloud-switch";
      runtimeInputs = [ googleCloudSdkWithGke kubectl fzf ];
      text = builtins.readFile ../scripts/gcloud-switch.sh;
    })
    (writeShellApplication {
      name = "gcloud-iap-ssh";
      runtimeInputs = [ googleCloudSdkWithGke fzf ];
      text = builtins.readFile ../scripts/gcloud-iap-ssh.sh;
    })
    (writeShellApplication {
      name = "hygiene-inspection";
      runtimeInputs = [
        fd git gh
        googleCloudSdkWithGke
        kubectl
      ];
      text = builtins.readFile ../scripts/hygiene-inspection.sh;
    })
    (writeShellApplication {
      name = "init-gh";
      runtimeInputs = [ gh openssh git ];
      text = builtins.readFile ../scripts/init-gh.sh;
    })
    (writeShellApplication {
      name = "wsl-spawn";
      runtimeInputs = [ curl coreutils gnugrep ];
      text = builtins.readFile ../scripts/wsl-spawn.sh;
    })
  ] ++ lib.optionals (!isMinimal) [
    zellij-main
    claude
    agy
    codex
    grok
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
    (writeShellApplication {
      name = "gcloud-iap-zellij-web";
      runtimeInputs = [
        googleCloudSdkWithGke
        fzf zellij-main
      ];
      text = builtins.readFile ../scripts/gcloud-iap-zellij-web.sh;
    })
  ];

  xdg.configFile."hygiene-expected-dotfiles".text = builtins.concatStringsSep "\n" expectedDotfiles + "\n";
  xdg.configFile."starship.toml".source = ../config/starship.toml;
  xdg.configFile."lazygit/config.yml".source = ../config/lazygit/config.yml;
  xdg.configFile."zellij/config.kdl".source = ../config/zellij/config.kdl;
  xdg.configFile."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;
  xdg.configFile."zellij/plugins/dim-unfocused.wasm".source = "${dim-unfocused-wasm}/share/zellij/plugins/dim-unfocused.wasm";

  home.file = (lib.optionalAttrs (!isMinimal) mcp.agyExtensionFiles) // {
    ".claude/settings.json".source = ../config/claude/settings.json;
  };

  home.activation.agyPluginImport = lib.mkIf (!isMinimal) (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${agy}/bin/agy plugin import gemini >/dev/null || true
    ''
  );

  home.activation.grokMcpSeed = lib.mkIf (!isMinimal) (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${grok-cfg.mcpSeed}
    ''
  );

  home.activation.agySettingsSeed = lib.mkIf (!isMinimal) (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      settings="$HOME/.gemini/antigravity-cli/settings.json"
      if [ ! -e "$settings" ]; then
        install -d "$(dirname "$settings")"
        install -m 0644 ${pkgs.writeText "agy-settings.json" (builtins.toJSON {
          enableTelemetry = false;
          chromiumSandbox = true;
        })} "$settings"
      fi
    ''
  );

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
      # Grok's counterpart. A GROK_CONFIG overlay rather than a config file:
      # Grok deletes ~/.grok/managed_config.toml whenever it refreshes its
      # model catalog, so the env is the durable slot. See home/grok.nix.
      export GROK_CONFIG=${lib.escapeShellArg grok-cfg.envOverlay}
      # Auto-compact at 256k tokens of context, matching `autoCompactWindow` in
      # config/claude/settings.json and `model_auto_compact_token_limit` in
      # home/codex.nix. Grok takes a percentage of the model's window instead of
      # a token count, and `[session]` is not overlay-allowlisted, so it arrives
      # as its own env var. See home/grok.nix.
      export GROK_AUTO_COMPACT_THRESHOLD_PERCENT=${toString grok-cfg.autoCompactThresholdPercent}
      export BROWSER=open-browser
      export EDITOR=micro
      # `entire login` defaults to the OS keyring via the D-Bus Secret Service.
      # WSL has a session bus but nothing provides org.freedesktop.secrets, so
      # the token write fails ("The name is not activatable") and the login is
      # thrown away. Persist to ~/.config/entire/tokens.json (0600) instead.
      export ENTIRE_TOKEN_STORE=file
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

      echo -e "\033[1;34m"
      echo " _   _     _               "
      echo "| |_| |__ (_)_  _____  ___ "
      echo "| __| '_ \| \ \/ / _ \/ __|"
      echo "| |_| | | | |>  < (_) \__ \\"
      echo " \__|_| |_|_/_/\_\___/|___/"
      echo -e "\033[0m"

      # Yazi wrapper for cwd syncing
      function yy() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }

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
      bindkey '^H'      backward-kill-word     # Ctrl+Backspace (WT sends bare ^H)

      # History
      bindkey '\e[1;2A' up-line-or-history     # Shift+Up
      bindkey '\e[1;2B' down-line-or-history   # Shift+Down
      bindkey '\e[1;2D' backward-word          # Shift+Left
      bindkey '\e[1;2C' forward-word           # Shift+Right
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
      user.name = "Thom Leggett";
      user.email = "thom@tteggel.org";
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
