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

  # Passed as `-c` rather than written to ~/.codex/config.toml. home-manager's
  # home.file installs read-only nix-store symlinks, and Codex writes that file
  # itself (per-project trust_level entries, the tui.model_availability_nux
  # counters), so it has to stay writable. Keeping it out of the repo also keeps
  # the project paths it records out of a public repository.
  tuiArgs = [
    "-c 'tui.status_line=[${lib.concatMapStringsSep "," builtins.toJSON statusLineItems}]'"
  ];
in {
  inherit statusLineItems tuiArgs;
}
