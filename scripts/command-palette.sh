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
  "exec:zsh -i -c yy	[Nav] Yazi file explorer	Ctrl+E"
  "exec:zsh -c 'fd --type f | fzf --preview \"bat --color=always {}\" | xargs -r zed'	[Nav] Find & open file"
  "exec:code-session	[Dev] Coding session"
  "exec:claude	[Dev] Claude Code"
  "exec:agy	[Dev] Antigravity CLI"
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
  "exec:zsh -c 'printf \"Repository for PAT: \"; read repo; ~/src/github.com/tteggel/.dotfiles/scripts/gh-sandbox-token.sh \"\$repo\"'	[Git] Create Sandbox PAT"
  "exec:gcloud-switch	[GCP] Switch project"
  "exec:gcloud-reauth	[GCP] Re-authenticate"
  "exec:gcloud-iap-zellij-web	[GCP] Connect to Zellij session via IAP"
  "exec:gcloud-iap-ssh	[GCP] IAP SSH into instance"
  "run:kubectl get pods	[K8s] List pods"
  "exec:zsh -c 'kubectl get pods --no-headers -o custom-columns=:metadata.name | fzf | xargs -r kubectl logs -f'	[K8s] Tail pod logs"
  "run:hygiene-inspection	[Sys] Hygiene inspection"
  "system:Rebuild system:if command -v nixos-rebuild >/dev/null 2>&1; then sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos; else home-manager switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix; fi	[Sys] Rebuild system"
  "system:Update system:git -C ~/src/github.com/tteggel/.dotfiles diff --quiet flake.lock || { echo 'Error: flake.lock has uncommitted changes'; exit 1; } && nix flake update --flake ~/src/github.com/tteggel/.dotfiles && if command -v nixos-rebuild >/dev/null 2>&1; then sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos; else home-manager switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix; fi && git -C ~/src/github.com/tteggel/.dotfiles add flake.lock && git -C ~/src/github.com/tteggel/.dotfiles commit -m 'Update flake inputs' && git -C ~/src/github.com/tteggel/.dotfiles push	[Sys] Update system"
)

# Right-align keybinding hints
term_width=$(tput cols 2>/dev/null || echo 80)
formatted=()
for cmd in "${commands[@]}"; do
  IFS=$'\t' read -r prefix desc hint <<< "$cmd"
  if [ -n "$hint" ]; then
    pad=$((term_width - ${#desc} - ${#hint} - 6))
    [ "$pad" -lt 2 ] && pad=2
    spaces=$(printf '%*s' "$pad" "")
    formatted+=("$prefix	$desc$spaces$hint")
  else
    formatted+=("$prefix	$desc")
  fi
done

selected=$(printf '%s\n' "${formatted[@]}" | fzf \
  --delimiter=$'\t' \
  --with-nth=2 \
  --preview-window=hidden \
  --prompt="Run> " \
  --height=~100% \
  --reverse \
  --no-info) || exit 0

entry="${selected%%	*}"
type="${entry%%:*}"
payload="${entry#*:}"

wait_for_key() {
  printf '\n\033[2m(press any key to close)\033[0m'
  read -rsn1 </dev/tty || true
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
    cd "$LAUNCH_CWD" || exit
    # shellcheck disable=SC2294
    eval "exec $payload"
    ;;
  run)
    cd "$LAUNCH_CWD" || exit
    eval "$payload" || true
    wait_for_key
    ;;
  system)
    cmd="${payload#*:}"
    bash -c "$cmd" || true
    wait_for_key
    ;;
esac

