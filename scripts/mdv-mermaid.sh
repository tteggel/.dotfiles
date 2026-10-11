# mdv, with ```mermaid fences drawn as diagrams.
#
# yazi's mdv-previewer shows mdv's ANSI text, so there is nowhere to put an
# image. Instead each mermaid fence goes through merman-cli, which draws it in
# Unicode box characters, and the drawing replaces the fence's source before
# mdv sees the file. A fence stays as source when merman cannot draw it: an
# unsupported family, a syntax error, a family merman only dumps as text
# (gantt, mindmap, ...), or a diagram wider than the preview.
#
# Installed as `mdv` on yazi's PATH. runtimeInputs puts the real mdv ahead of
# this script on its own PATH, so `mdv` below is the real one.

# The previewer keys its render cache on `mdv --version`. Fold merman's version
# in so previews cached before this wrapper, or by another merman, re-render.
if [ "$*" = --version ]; then
  mdv --version
  merman-cli --version
  exit
fi

# The previewer passes the file last. Anything else (stdin, --help, a file with
# no mermaid fence) goes straight through.
file=${!#}
if [ "$#" -eq 0 ] || [ ! -f "$file" ] ||
  ! grep -Eq '^ {0,3}(```|~~~)[[:space:]]*mermaid' "$file"; then
  exec mdv "$@"
fi

cols=80
prev=
for arg in "$@"; do
  case $prev in -c | --cols) cols=$arg ;; esac
  case $arg in --cols=*) cols=${arg#*=} ;; esac
  prev=$arg
done
[[ $cols =~ ^[0-9]+$ ]] || cols=80

# Print the drawing of mermaid source $2, at most $1 columns wide, or fail.
# Flowchart and sequence may switch to a compact layout to fit; the other
# families refuse --ascii-layout-profile auto, hence the canonical retry.
draw() {
  local profile
  for profile in auto canonical; do
    printf '%s' "$2" |
      merman-cli render - --format unicode --ascii-report \
        --ascii-max-width "$1" --ascii-overflow error \
        --ascii-layout-profile "$profile" \
        --resource-profile constrained --operation-timeout-ms 2000 \
        --output - 2>/dev/null |
      jq -ej 'select(.projection == "diagrammatic") | .text' && return
  done
  return 1
}

open_re='^( {0,3})(`{3,}|~{3,})(.*)$'
close_re='^ {0,3}(`{3,}|~{3,})[[:space:]]*$'
atx_re='^ {0,3}(#{1,6})([[:space:]]|$)'
setext_re='^ {0,3}(=+|-+)[[:space:]]*$'

# mdv frames a code block in 4 columns, indents it one more per heading level,
# and wraps longer lines, which would shred a drawing. So track the last
# heading's level to size each diagram. Too high only narrows the drawing (and
# smart indent only ever indents less); too low makes mdv wrap it.
level=0
fence=   # the open code fence, while inside a code block
indent=  # its indentation
block=   # the whole mermaid fence so far, kept to print back unchanged
source=  # the mermaid fence's contents
last=    # the previous line outside code, for setext underlines
rewrite() {
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [ -z "$fence" ]; then
      if [[ $line =~ $open_re ]] &&
        ! [[ ${BASH_REMATCH[2]} == '`'* && ${BASH_REMATCH[3]} == *'`'* ]]; then
        indent=${BASH_REMATCH[1]}
        fence=${BASH_REMATCH[2]}
        read -r lang _ <<<"${BASH_REMATCH[3]}"
        if [ "$lang" = mermaid ]; then
          block=$line$'\n'
          source=
          continue
        fi
      elif [[ $line =~ $atx_re ]]; then
        level=${#BASH_REMATCH[1]}
      elif [[ $line =~ $setext_re ]] && [[ $last == *[^[:space:]]* ]]; then
        # A --- under a paragraph could equally be a rule, so an underline
        # only ever raises the level.
        if [[ ${BASH_REMATCH[1]} == =* ]]; then underline=1; else underline=2; fi
        if [ "$underline" -gt "$level" ]; then level=$underline; fi
      fi
      last=$line
      printf '%s\n' "$line"
      continue
    fi

    if [[ $line =~ $close_re ]] && [ "${BASH_REMATCH[1]:0:1}" = "${fence:0:1}" ] &&
      [ "${#BASH_REMATCH[1]}" -ge "${#fence}" ]; then
      if [ -n "$block" ]; then
        if diagram=$(draw $((cols - 4 - level - ${#indent})) "$source"); then
          printf '%s%smermaid\n' "$indent" "$fence"
          while IFS= read -r row; do
            printf '%s%s\n' "$indent" "$row"
          done <<<"$diagram"
          printf '%s%s\n' "$indent" "$fence"
        else
          printf '%s%s\n' "$block" "$line"
        fi
        block=
      else
        printf '%s\n' "$line"
      fi
      fence=
      last=
      continue
    fi

    if [ -n "$block" ]; then
      block+=$line$'\n'
      source+=$line$'\n'
    else
      printf '%s\n' "$line"
    fi
  done
  # An unclosed mermaid fence runs to the end of the file: leave it as source.
  printf '%s' "$block"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Same basename, so mdv treats the copy exactly as it would the original.
copy=$tmp/$(basename -- "$file")
rewrite <"$file" >"$copy"
mdv "${@:1:$#-1}" "$copy"
