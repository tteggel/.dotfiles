        SRC_ROOT="$HOME/src/github.com"

        start_session() {
          local dir="$1"
          local name
          name=$(basename "$dir")
          cd "$dir" && exec zellij -s "$name" -n ~/.config/zellij/layouts/code.kdl
        }

        new_session() {
          dir=$(zoxide query -i 2>/dev/null) || return 1
          start_session "$dir"
        }

        clone_gh_repo() {
          repos=$(gh repo list --limit 50 --json nameWithOwner,updatedAt --jq 'sort_by(.updatedAt) | reverse | .[].nameWithOwner' 2>&1) || {
            echo "Failed to fetch repos: $repos" >&2
            echo "Check 'gh auth status'" >&2
            read -r -n 1
            return 1
          }

          org_repos=""
          for org in $(gh org list 2>/dev/null); do
            org_repos="$org_repos
$(gh repo list "$org" --limit 50 --json nameWithOwner,updatedAt --jq 'sort_by(.updatedAt) | reverse | .[].nameWithOwner' 2>/dev/null)"
          done

          all_repos=$(printf '%s\n%s' "$repos" "$org_repos" | sed '/^$/d' | sort -u)

          if [ -z "$all_repos" ]; then
            echo "No repos found." >&2
            read -r -n 1
            return 1
          fi

          repo=$(echo "$all_repos" | fzf --prompt="GitHub repo> " --height=~50% --reverse) || return 1

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
            no_client="${no_client}${entry}"$'\n'
          elif echo "$line" | grep -q "(current session)"; then
            entry="$name (current)"
            has_client="${has_client}${entry}"$'\n'
          elif echo "$line" | grep -q "attached"; then
            entry="$name (attached)"
            has_client="${has_client}${entry}"$'\n'
          else
            no_client="${no_client}${name}"$'\n'
          fi
        done <<< "$sessions"

        NEW_ENTRY="[+] New session       (Ctrl+N)"
        GH_ENTRY="[+] Clone GitHub repo (Ctrl+G)"
        REMOTE_ENTRY="[+] Clone remote      (Ctrl+U)"

        menu="${no_client}${has_client}$NEW_ENTRY
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

