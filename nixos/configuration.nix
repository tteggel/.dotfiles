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
    eza
    bat
    fd
    ripgrep
    fzf
    zoxide
    delta
    lazygit
    difftastic
    zellij
    google-cloud-sdk
    kubectl
    inputs.llm-agents.packages.x86_64-linux.claude-code
    inputs.llm-agents.packages.x86_64-linux.gemini-cli
    inputs.llm-agents.packages.x86_64-linux.codex
    starship
    (writeShellApplication {
      name = "code-session";
      runtimeInputs = [ zellij ];
      text = ''
        if [ -z "''${ZELLIJ:-}" ]; then
          zellij --layout /etc/zellij/layouts/code.kdl
        else
          zellij action new-tab --layout /etc/zellij/layouts/code.kdl --cwd "$(pwd)" --name code
          zellij action go-to-previous-tab
          zellij action close-tab
        fi
      '';
    })
    (writeShellApplication {
      name = "command-palette";
      runtimeInputs = [ fzf zellij ];
      text = ''
        commands=(
          "code-session:Start coding session layout"
          "claude:Claude Code"
          "gemini:Gemini CLI"
          "lazygit:Git UI"
          "gh pr list:List pull requests"
          "gh pr create:Create pull request"
          "gh pr checkout:Checkout pull request"
          "gh repo clone:Clone a GitHub repo"
          "gcloud-switch:Switch GCP project and fetch kube credentials"
          "nixos-rebuild:sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles"
          "update-system:nix flake update --flake ~/src/github.com/tteggel/.dotfiles && sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles && git -C ~/src/github.com/tteggel/.dotfiles add flake.lock && git -C ~/src/github.com/tteggel/.dotfiles commit -m 'Update flake inputs' && git -C ~/src/github.com/tteggel/.dotfiles push"
        )
        selected=$(printf '%s\n' "''${commands[@]}" | fzf --delimiter=: --with-nth=2 --prompt="Run> " --height=~100% --reverse --no-info) || exit 0
        cmd="''${selected%%:*}"
        zellij action toggle-floating-panes
        zellij run -- bash -c "$cmd"
      '';
    })
    (writeShellApplication {
      name = "gcloud-switch";
      runtimeInputs = [ google-cloud-sdk kubectl fzf ];
      text = ''
        project=$(gcloud projects list --format="value(projectId)" | fzf --prompt="Project> " --height=~100% --reverse) || exit 0
        gcloud config set project "$project"

        cluster=$(gcloud container clusters list --format="csv[no-heading](name,location)" 2>/dev/null | fzf --prompt="Cluster> " --height=~100% --reverse) || exit 0
        cluster_name="''${cluster%%,*}"
        cluster_location="''${cluster##*,}"
        gcloud container clusters get-credentials "$cluster_name" --region "$cluster_location"

        echo "Switched to project=$project cluster=$cluster_name"
      '';
    })
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
  environment.etc."zellij/config.kdl".source = ../config/zellij/config.kdl;
  environment.etc."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;

  networking.hostName = "thixos";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    promptInit = "";  # disable default prompt, we use starship
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 10000;
    histFile = "$HOME/.zsh_history";
    setOptions = [
      "HIST_FCNTL_LOCK"
      "HIST_IGNORE_DUPS"
      "HIST_IGNORE_SPACE"
      "SHARE_HISTORY"
    ];
    shellAliases = {
      ls = "eza";
      ll = "eza -l --git";
      la = "eza -la --git";
      lt = "eza -T --git-ignore";
      cat = "bat --paging=never";
      grep = "rg";
      find = "fd";
    };
    interactiveShellInit = ''
      export STARSHIP_CONFIG=/etc/starship.toml
      export ZELLIJ_CONFIG_DIR=/etc/zellij
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      init-gh
      eval "$(starship init zsh)"

      # Auto-attach to zellij session (or start one) unless already inside zellij
      if [ -z "$ZELLIJ" ]; then
        zellij attach -c default
      fi
      eval "$(fzf --zsh)"
      eval "$(zoxide init zsh)"

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

  programs.nix-ld.enable = true;

  users.users = {
    thom = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
    };
  };

  system.activationScripts.wezterm.text = ''
    cp ${../config/wezterm.lua} /mnt/c/Users/thom/.wezterm.lua
  '';

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.tailscale.enable = true;
}
