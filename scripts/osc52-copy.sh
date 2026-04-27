#!/usr/bin/env bash
LOG="/tmp/zellij-debug.log"
echo "--- osc52-copy ran at $(date) ---" >> "$LOG"

# Read from stdin, encode to base64, and emit the OSC 52 escape sequence.
# This securely sets the clipboard in the outer terminal (e.g. WezTerm) 
# even across SSH or isolated WSL environments.
# We write to /dev/tty so the escape sequence reaches the terminal.

# Read all input into a variable. 
# We don't use 'tr -d \n' because we want to preserve the copied text's line breaks.
text=$(cat)
echo "Received text length: ${#text}" >> "$LOG"

# Convert to base64, removing the wrapped newlines from base64 output
b64=$(printf "%s" "$text" | base64 | tr -d '\n')

# Emit OSC 52
echo "Emitting OSC 52 sequence to /dev/tty..." >> "$LOG"
if printf "\033]52;c;%s\a" "$b64" > /dev/tty 2>>"$LOG"; then
  echo "Emission successful." >> "$LOG"
else
  echo "Emission failed!" >> "$LOG"
fi
