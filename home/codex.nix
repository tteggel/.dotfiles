{ lib }: let
  # Codex status line, mirroring scripts/claude-statusline.sh so both CLIs read
  # the same. Item vocabulary is codex 0.147.0's; `status_line` REPLACES the
  # default list rather than extending it, so run-state is listed explicitly to
  # keep the spinner.
  statusLineItems = [
    "project-name"
    "git-branch"
    "run-state"
    "model-with-reasoning"
    "context-remaining"
    "total-input-tokens"
    "total-output-tokens"
    "five-hour-limit"
    "weekly-limit"
  ];

  # Auto-compact at 256k tokens, the same point Claude gets from
  # `autoCompactWindow` in config/claude/settings.json and Grok from
  # home/grok.nix. Codex ships no default of its own (`auto_compact_token_limit`
  # is null for every entry in `codex debug models`), so without this compaction
  # waits for the model's own window -- 272k on the current gpt-5.x models. The
  # companion `model_auto_compact_token_limit_scope` defaults to `total`, i.e.
  # the whole prompt including the fixed prefix, which is what the status line's
  # `context-remaining` item counts down.
  autoCompactTokenLimit = 256000;

  # Passed as `-c` rather than written to ~/.codex/config.toml. home-manager's
  # home.file installs read-only nix-store symlinks, and Codex writes that file
  # itself (per-project trust_level entries, the tui.model_availability_nux
  # counters), so it has to stay writable. Keeping it out of the repo also keeps
  # the project paths it records out of a public repository.
  configArgs = [
    "-c 'tui.status_line=[${lib.concatMapStringsSep "," builtins.toJSON statusLineItems}]'"
    "-c model_auto_compact_token_limit=${toString autoCompactTokenLimit}"
  ];
in {
  inherit statusLineItems autoCompactTokenLimit configArgs;
}
