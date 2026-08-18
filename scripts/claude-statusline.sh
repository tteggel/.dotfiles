# Mirrors the Codex status line, using Claude Code's statusLine payload.
#
# Codex (tui/src/status/card.rs), configured in home/mcp.nix via tui.status_line:
#   project-name · git-branch · run-state · model-with-reasoning ·
#   context-remaining · total-input-tokens · total-output-tokens ·
#   five-hour-limit · weekly-limit
#
# Both Codex limit items are documented as "Remaining usage on the <window>
# usage limit (omitted when unavailable)", so these are REMAINING percentages.
# Claude's five_hour / seven_day windows map onto Codex's five-hour / weekly.
#
# run-state has no equivalent here: Claude renders its own spinner.
# git-branch has no equivalent either -- the payload's `workspace` object
# carries current_dir/project_dir/repo but no branch, so we ask git.
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')
branch=$(git -C "$dir" branch --show-current 2>/dev/null) || branch=""

printf '%s' "$input" | jq -r --arg branch "$branch" '
  # Seconds-until -> compact duration. Rounds rather than floors: for a
  # countdown, reporting 7199s as "1h" is worse than reporting it as "2h".
  def dur:
    if . <= 0 then "now"
    elif . < 3600 then "\(. / 60 | round)m"
    elif . < 86400 then "\(. / 3600 | round)h"
    else "\(. / 86400 | round)d"
    end;

  # Token count -> compact. Codex renders these as "<n> in" / "<n> out".
  def tok:
    if . >= 1000000 then "\((. / 100000 | round) / 10)M"
    elif . >= 1000 then "\(. / 1000 | floor)k"
    else "\(.)"
    end;

  # rate_limits is subscriber-only and absent until the first API response, so
  # an unavailable window drops out of the line entirely, as Codex does.
  def limit($label):
    if type != "object" then empty
    else "\($label) \(100 - (.used_percentage // 0) | round)%"
         + (if .resets_at then " (resets \((.resets_at - now) | dur))" else "" end)
    end;

  [ # repo identity comes from the origin remote; fall back to the dir name
    ( .workspace.repo.name
      // (.workspace.project_dir // "" | split("/") | map(select(length > 0)) | last)
      // empty ),

    (if $branch == "" then empty else $branch end),

    ( (.model.display_name // .model.id // "claude")
      + (if .effort.level then " \(.effort.level)" else "" end) ),

    # context_window.current_usage is null until the first API response
    ( .context_window
      | if (.total_input_tokens // 0) > 0
        then "\(.remaining_percentage // (100 - (.used_percentage // 0)) | round)% context left"
        else empty
        end ),

    ( .context_window
      | if (.total_input_tokens // 0) > 0 then "\(.total_input_tokens | tok) in" else empty end ),
    ( .context_window
      | if (.total_output_tokens // 0) > 0 then "\(.total_output_tokens | tok) out" else empty end ),

    (.rate_limits.five_hour | limit("5h")),
    (.rate_limits.seven_day | limit("weekly"))
  ]
  | join(" · ")
'
