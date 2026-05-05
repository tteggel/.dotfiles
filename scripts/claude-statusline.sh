jq -r '
  (.context_window.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $tok
  | (.context_window.used_percentage // 0) as $pct
  | (.model.display_name // .model.id // "claude") as $m
  | if $tok > 0
    then "\($m) · \($tok / 1000 | floor)k tok (\($pct | floor)%)"
    else $m
    end
'
