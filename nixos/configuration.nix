{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: let
  bespoke-zellij = inputs.dim-unfocused.packages.x86_64-linux;
  zellij-main = bespoke-zellij.zellij;
  dim-unfocused-wasm = bespoke-zellij.dim-unfocused;
  expectedDotfiles = [
    ".ssh"
    ".cache"
    ".local"
    ".config/gcloud"
    ".config/gh"
    ".config/claude"
    ".claude"
    ".zsh_history"
    ".zoxide.db"
    ".zoxide.db.zo"
    ".sudo_as_admin_successful"
    ".init-gh-completed"
    ".zcompdump*"
    ".zsh_sessions"
    ".wget-hsts"
    "src"
  ];
in {
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
    zellij-main
    (google-cloud-sdk.withExtraComponents [
      google-cloud-sdk.components.gke-gcloud-auth-plugin
    ])
    kubectl
    inputs.llm-agents.packages.x86_64-linux.claude-code
    inputs.llm-agents.packages.x86_64-linux.gemini-cli
    inputs.llm-agents.packages.x86_64-linux.codex
    micro
    (writeShellApplication {
      name = "zed";
      text = ''
        # Find zed.exe via WSL interop PATH
        ZED_EXE="$(command -v zed.exe 2>/dev/null || echo "/mnt/c/Users/thom/AppData/Local/Programs/Zed/zed.exe")"

        args=()
        for arg in "$@"; do
          if [[ "$arg" == -* ]]; then
            args+=("$arg")
          elif [[ -e "$arg" || -d "$arg" ]]; then
            args+=("$(wslpath -w "$arg")")
          else
            args+=("$arg")
          fi
        done

        "$ZED_EXE" --wait "''${args[@]}"
      '';
    })
    starship
    (writeShellApplication {
      name = "session-picker";
      runtimeInputs = [ zellij-main fzf zoxide gh git ];
      text = ''
        SRC_ROOT="$HOME/src/github.com"

        start_session() {
          local dir="$1"
          local name
          name=$(basename "$dir")
          cd "$dir" && exec zellij -s "$name" -n /etc/zellij/layouts/code.kdl
        }

        new_session() {
          dir=$(zoxide query -i 2>/dev/null) || return 1
          start_session "$dir"
        }

        clone_gh_repo() {
          repo=$(gh repo list --limit 50 --sort updated --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null | \
            cat - <(for org in $(gh org list 2>/dev/null); do
              gh repo list "$org" --limit 50 --sort updated --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null
            done) | \
            sort -u | \
            fzf --prompt="GitHub repo> " --height=~50% --reverse) || return 1

          owner=$(dirname "$repo")
          name=$(basename "$repo")
          target="$SRC_ROOT/$owner/$name"

          if [ -d "$target" ]; then
            start_session "$target"
          else
            mkdir -p "$SRC_ROOT/$owner"
            gh repo clone "$repo" "$target" || return 1
            start_session "$target"
          fi
        }

        clone_remote() {
          printf "Remote URL: "
          read -r url
          [ -z "$url" ] && return 1

          # Extract repo name from URL
          name=$(basename "$url" .git)
          target="$HOME/src/$name"

          if [ -d "$target" ]; then
            start_session "$target"
          else
            git clone "$url" "$target" || return 1
            start_session "$target"
          fi
        }

        sessions=$(zellij list-sessions -n -s 2>/dev/null || true)

        if [ -z "$sessions" ]; then
          new_session
          exit $?
        fi

        # Build menu: annotate and sort (no-client first), add new-session entry
        menu=""
        no_client=""
        has_client=""
        while IFS= read -r line; do
          name=$(echo "$line" | awk '{print $1}')
          if echo "$line" | grep -q "EXITED"; then
            entry="$name (EXITED)"
            no_client="''${no_client}''${entry}"$'\n'
          elif echo "$line" | grep -q "(current session)"; then
            entry="$name (current)"
            has_client="''${has_client}''${entry}"$'\n'
          elif echo "$line" | grep -q "attached"; then
            entry="$name (attached)"
            has_client="''${has_client}''${entry}"$'\n'
          else
            no_client="''${no_client}''${name}"$'\n'
          fi
        done <<< "$sessions"

        NEW_ENTRY="[+] New session       (Ctrl+N)"
        GH_ENTRY="[+] Clone GitHub repo (Ctrl+G)"
        REMOTE_ENTRY="[+] Clone remote      (Ctrl+U)"

        menu="''${no_client}''${has_client}$NEW_ENTRY
$GH_ENTRY
$REMOTE_ENTRY"

        pick=$(echo "$menu" | fzf --prompt="Zellij session> " --height=~50% --reverse \
          --bind "ctrl-n:become(echo '$NEW_ENTRY')" \
          --bind "ctrl-g:become(echo '$GH_ENTRY')" \
          --bind "ctrl-u:become(echo '$REMOTE_ENTRY')") || exit 1

        if echo "$pick" | grep -q "New session"; then
          new_session
        elif echo "$pick" | grep -q "Clone GitHub"; then
          clone_gh_repo
        elif echo "$pick" | grep -q "Clone remote"; then
          clone_remote
        else
          session_name=$(echo "$pick" | awk '{print $1}')
          exec zellij attach "$session_name"
        fi
      '';
    })
    (writeShellApplication {
      name = "claude-session";
      runtimeInputs = [ fzf inputs.llm-agents.packages.x86_64-linux.claude-code ];
      text = ''
        pick=$(printf 'New session\nResume session' | fzf --prompt="Claude> " --height=~50% --reverse) || exit 0
        if [ "$pick" = "Resume session" ]; then
          exec claude --resume
        else
          exec claude
        fi
      '';
    })
    (writeShellApplication {
      name = "gemini-session";
      runtimeInputs = [ fzf inputs.llm-agents.packages.x86_64-linux.gemini-cli ];
      text = ''
        pick=$(printf 'New session\nResume session' | fzf --prompt="Gemini> " --height=~50% --reverse) || exit 0
        if [ "$pick" = "Resume session" ]; then
          exec gemini --resume latest
        else
          exec gemini
        fi
      '';
    })
    (writeShellApplication {
      name = "code-session";
      runtimeInputs = [ zellij-main ];
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
      runtimeInputs = [ fzf zellij-main fd zoxide ];
      text = ''
        # Prevent multiple palette instances
        exec 9>/tmp/command-palette.lock
        if ! flock -n 9; then
          exit 0
        fi

        LAUNCH_CWD="$PWD"

        # Types: action (zellij action, hides overlay first)
        #        exec   (interactive, takes over the overlay pane)
        #        run    (shows output in overlay, then press-any-key)
        #        system (like run, but name:cmd payload format)
        commands=(
          "action:zellij action new-pane	[Pane] New pane	Ctrl+Shift+N"
          "action:zellij action new-pane --floating	[Pane] New floating pane"
          "action:zellij action new-pane --direction down	[Pane] Split down"
          "action:zellij action new-pane --direction right	[Pane] Split right"
          "action:zellij action close-pane	[Pane] Close pane	Ctrl+Shift+W"
          "action:zellij action toggle-fullscreen	[Pane] Toggle fullscreen	Ctrl+Shift+Z"
          "action:zellij action toggle-floating-panes	[Pane] Toggle floating panes"
          "action:zellij action rename-pane	[Pane] Rename pane"
          "action:zellij action edit-scrollback	[Pane] Edit scrollback"
          "action:zellij action move-focus left	[Pane] Focus left	Ctrl+Shift+H"
          "action:zellij action move-focus down	[Pane] Focus down	Ctrl+Shift+J"
          "action:zellij action move-focus up	[Pane] Focus up	Ctrl+Shift+K"
          "action:zellij action move-focus right	[Pane] Focus right	Ctrl+Shift+L"
          "action:zellij action resize increase	[Pane] Grow pane	Ctrl+Shift+="
          "action:zellij action resize decrease	[Pane] Shrink pane	Ctrl+Shift+-"
          "action:zellij action new-tab	[Tab] New tab	Ctrl+Shift+T"
          "action:zellij action close-tab	[Tab] Close tab"
          "action:zellij action rename-tab	[Tab] Rename tab"
          "action:zellij action go-to-previous-tab	[Tab] Previous tab	Ctrl+Shift+["
          "action:zellij action go-to-next-tab	[Tab] Next tab	Ctrl+Shift+]"
          "action:zellij action go-to-tab 1	[Tab] Tab 1	Ctrl+Shift+1"
          "action:zellij action go-to-tab 2	[Tab] Tab 2	Ctrl+Shift+2"
          "action:zellij action go-to-tab 3	[Tab] Tab 3	Ctrl+Shift+3"
          "action:zellij action go-to-tab 4	[Tab] Tab 4	Ctrl+Shift+4"
          "action:zellij action go-to-tab 5	[Tab] Tab 5	Ctrl+Shift+5"
          "action:zellij action next-swap-layout	[Layout] Swap layout	Ctrl+Shift+Space"
          "action:zellij action switch-mode scroll	[Mode] Scroll mode	Ctrl+Shift+S"
          "action:zellij action switch-mode locked	[Mode] Lock mode	Ctrl+Shift+G"
          "session:zellij action detach	[Session] Detach	Ctrl+Shift+Q"
          "session:zellij action quit	[Session] Quit Zellij"
          "exec:session-picker	[Session] Switch session	Ctrl+Shift+O"
          "exec:zsh -c 'cd \"\$(zoxide query -i)\" && exec zsh'	[Nav] Jump to directory"
          "exec:zsh -c 'fd --type f | fzf --preview \"bat --color=always {}\" | xargs -r zed'	[Nav] Find & open file"
          "exec:code-session	[Dev] Coding session"
          "exec:claude-session	[Dev] Claude Code"
          "exec:gemini-session	[Dev] Gemini CLI"
          "exec:codex	[Dev] Codex CLI"
          "exec:lazygit	[Git] Git UI (lazygit)"
          "run:gh pr list	[Git] List pull requests"
          "exec:gh pr create	[Git] Create pull request"
          "exec:gh pr checkout	[Git] Checkout pull request"
          "run:gh repo clone	[Git] Clone repo"
          "run:gh issue list	[Git] List issues"
          "exec:gh issue create	[Git] Create issue"
          "run:gh run list	[Git] CI/CD runs"
          "exec:gh run watch	[Git] Watch CI/CD run"
          "exec:gcloud-switch	[GCP] Switch project"
          "exec:gcloud-reauth	[GCP] Re-authenticate"
          "run:kubectl get pods	[K8s] List pods"
          "exec:zsh -c 'kubectl get pods --no-headers -o custom-columns=:metadata.name | fzf | xargs -r kubectl logs -f'	[K8s] Tail pod logs"
          "run:hygiene-inspection	[Sys] Hygiene inspection"
          "system:Rebuild NixOS:sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles	[Sys] Rebuild NixOS"
          "system:Update system:git -C ~/src/github.com/tteggel/.dotfiles diff --quiet flake.lock || { echo 'Error: flake.lock has uncommitted changes'; exit 1; } && nix flake update --flake ~/src/github.com/tteggel/.dotfiles && sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles && git -C ~/src/github.com/tteggel/.dotfiles add flake.lock && git -C ~/src/github.com/tteggel/.dotfiles commit -m 'Update flake inputs' && git -C ~/src/github.com/tteggel/.dotfiles push	[Sys] Update system"
        )

        # Right-align keybinding hints
        term_width=$(tput cols 2>/dev/null || echo 80)
        formatted=()
        for cmd in "''${commands[@]}"; do
          IFS=$'\t' read -r prefix desc hint <<< "$cmd"
          if [ -n "$hint" ]; then
            pad=$((term_width - ''${#desc} - ''${#hint} - 6))
            [ "$pad" -lt 2 ] && pad=2
            spaces=$(printf '%*s' "$pad" "")
            formatted+=("$prefix	$desc$spaces$hint")
          else
            formatted+=("$prefix	$desc")
          fi
        done

        selected=$(printf '%s\n' "''${formatted[@]}" | fzf \
          --delimiter=$'\t' \
          --with-nth=2 \
          --preview-window=hidden \
          --prompt="Run> " \
          --height=~100% \
          --reverse \
          --no-info) || exit 0

        entry="''${selected%%	*}"
        type="''${entry%%:*}"
        payload="''${entry#*:}"

        wait_for_key() {
          printf '\n\033[2m(press any key to close)\033[0m'
          read -rsn1
        }

        case "$type" in
          action)
            zellij action toggle-floating-panes
            exec bash -c "$payload"
            ;;
          session)
            exec bash -c "$payload"
            ;;
          exec)
            cd "$LAUNCH_CWD"
            # shellcheck disable=SC2294
            eval "exec $payload"
            ;;
          run)
            cd "$LAUNCH_CWD"
            eval "$payload" || true
            wait_for_key
            ;;
          system)
            cmd="''${payload#*:}"
            bash -c "$cmd" || true
            wait_for_key
            ;;
        esac
      '';
    })
    (writeShellApplication {
      name = "gcloud-reauth";
      runtimeInputs = [ (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ]) ];
      text = ''
        gcloud auth login
        gcloud auth application-default login
        echo "Reauth complete."
      '';
    })
    (writeShellApplication {
      name = "gcloud-switch";
      runtimeInputs = [ (google-cloud-sdk.withExtraComponents [
        google-cloud-sdk.components.gke-gcloud-auth-plugin
      ]) kubectl fzf ];
      text = ''
        if ! gcloud projects list --format="value(projectId)" --limit=1 &>/dev/null; then
          echo "Not authenticated. Logging in..."
          gcloud auth login
          gcloud auth application-default login
        fi

        project=$(gcloud projects list --format="value(projectId)" --filter="NOT projectId:sys-*" | fzf --prompt="Project> " --height=~100% --reverse) || exit 0
        gcloud config set project "$project"

        clusters=$(gcloud container clusters list --format="csv[no-heading](name,location)" 2>/dev/null)
        count=$(echo "$clusters" | grep -c . || true)

        if [ "$count" -eq 0 ]; then
          echo "Switched to project=$project (no clusters)"
          exit 0
        elif [ "$count" -eq 1 ]; then
          cluster="$clusters"
        else
          cluster=$(echo "$clusters" | fzf --prompt="Cluster> " --height=~100% --reverse) || exit 0
        fi

        cluster_name="''${cluster%%,*}"
        cluster_location="''${cluster##*,}"
        gcloud container clusters get-credentials "$cluster_name" --region "$cluster_location"

        echo "Switched to project=$project cluster=$cluster_name"
      '';
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
      text = ''
        RED=$'\033[0;31m'
        YELLOW=$'\033[0;33m'
        GREEN=$'\033[0;32m'
        BOLD=$'\033[1m'
        NC=$'\033[0m'

        issues=0
        warnings=0

        issue() { printf '%s  ISSUE:%s %s\n' "$RED" "$NC" "$1"; issues=$((issues + 1)); }
        warn()  { printf '%s  WARN:%s  %s\n' "$YELLOW" "$NC" "$1"; warnings=$((warnings + 1)); }
        section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$NC"; }

        ALLOWLIST="/etc/hygiene-expected-dotfiles"

        # --- Unmanaged dotfiles ---
        section "Home directory"
        while IFS= read -r entry; do
          name="''${entry#"$HOME"/}"
          matched=false
          while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            # shellcheck disable=SC2254
            case "$name" in
              $pattern) matched=true; break ;;
            esac
          done < "$ALLOWLIST"
          if [ "$matched" = false ]; then
            issue "Unmanaged: ~/$name"
          fi
        done < <(find "$HOME" -maxdepth 1 -mindepth 1 | sort)

        # --- Dirty git repos ---
        section "Git repositories"
        while IFS= read -r gitdir; do
          repo="''${gitdir%/.git}"
          name="''${repo#"$HOME"/}"
          pushd "$repo" > /dev/null || continue

          if [ -n "$(timeout 5 git status --porcelain 2>/dev/null)" ]; then
            issue "Dirty repo: $name (uncommitted changes)"
          fi

          stash_count=$(timeout 5 git stash list 2>/dev/null | wc -l)
          if [ "$stash_count" -gt 0 ]; then
            issue "Stashes in: $name ($stash_count stash(es))"
          fi

          # Check for unpushed commits on current branch
          upstream=$(timeout 5 git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
          if [ -n "$upstream" ]; then
            unpushed=$(timeout 5 git rev-list "$upstream"..HEAD 2>/dev/null | wc -l)
            if [ "$unpushed" -gt 0 ]; then
              issue "Unpushed commits: $name ($unpushed commit(s))"
            fi
          fi

          popd > /dev/null || true
        done < <(timeout 10 fd --type d --hidden --no-ignore --glob '.git' "$HOME/src" 2>/dev/null)

        # --- Imperative nix packages ---
        section "Nix"
        if [ -d "$HOME/.nix-profile/bin" ] || nix-env -q 2>/dev/null | grep -q .; then
          issue "Imperative nix packages found (use flake instead)"
        fi

        # --- User crontabs ---
        section "Cron"
        if crontab -l 2>/dev/null | grep -qv '^#\|^$'; then
          issue "User crontab entries found"
        fi

        # --- Unmanaged systemd user units ---
        section "Systemd user units"
        if [ -d "$HOME/.config/systemd/user" ]; then
          unit_count=$(find "$HOME/.config/systemd/user" -type f 2>/dev/null | wc -l)
          if [ "$unit_count" -gt 0 ]; then
            issue "Unmanaged systemd user units ($unit_count file(s) in ~/.config/systemd/user)"
          fi
        fi

        # --- Warnings: credentials & state ---
        section "Credentials & state"
        if [ -d "$HOME/.ssh" ]; then
          key_count=$(find "$HOME/.ssh" -name '*.pub' 2>/dev/null | wc -l)
          if [ "$key_count" -gt 0 ]; then
            warn "SSH keys present ($key_count key(s))"
          fi
        fi

        if [ -d "$HOME/.gnupg" ]; then
          warn "GPG directory present"
        fi

        if gh auth status &>/dev/null; then
          warn "gh authenticated"
        fi

        if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
          warn "gcloud authenticated"
        fi

        if kubectl config current-context &>/dev/null; then
          warn "kubectl context configured"
        fi

        if [ -d "$HOME/.docker" ]; then
          warn "Docker state present (~/.docker)"
        fi

        # Large /tmp files (>100MB)
        large_tmp=$(find /tmp -maxdepth 2 -user "$(whoami)" -size +100M 2>/dev/null | wc -l)
        if [ "$large_tmp" -gt 0 ]; then
          warn "Large files in /tmp ($large_tmp file(s) >100MB)"
        fi

        # --- Summary ---
        printf '\n%s---%s\n' "$BOLD" "$NC"
        if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
          printf '%sClean: safe to move.%s\n' "$GREEN" "$NC"
        else
          [ "$issues" -gt 0 ] && printf '%s%d issue(s)%s ' "$RED" "$issues" "$NC"
          [ "$warnings" -gt 0 ] && printf '%s%d warning(s)%s ' "$YELLOW" "$warnings" "$NC"
          printf '\n'
        fi
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

  environment.etc."hygiene-expected-dotfiles".text =
    builtins.concatStringsSep "\n" expectedDotfiles + "\n";
  environment.etc."starship.toml".source = ../config/starship.toml;
  environment.etc."zellij/config.kdl".source = ../config/zellij/config.kdl;
  environment.etc."zellij/layouts/code.kdl".source = ../config/zellij/layouts/code.kdl;
  environment.etc."zellij/plugins/dim-unfocused.wasm".source =
    "${dim-unfocused-wasm}/share/zellij/plugins/dim-unfocused.wasm";

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
