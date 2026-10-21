{ pkgs }: rec {
  # Loads the direnv environment for the working directory into the current
  # shell, so agents get each project's devshell without having to work out
  # `nix develop`. They start from zellij rather than an interactive shell, so
  # direnv's prompt hook never runs for them. Claude sources this before every
  # Bash command (CLAUDE_ENV_FILE); the bash Codex runs each command in sources
  # it at startup (BASH_ENV, put back by `bash` below). direnv re-evaluates
  # when flake.nix, flake.lock or .envrc change.
  loader = pkgs.writeText "agent-direnv.sh" ''
    # Codex's outer shell sources its shell snapshot after this, which resets
    # PATH. The `exec bash -c` that shell ends with sources this again and loads.
    case ''${BASH_EXECUTION_STRING-} in
      *shell_snapshots/*) return 0 ;;
    esac

    # PATH differs from the last load (a snapshot reset it, say), so direnv's
    # record of what it loaded is stale: load from scratch. Otherwise, as in a
    # bash started by a command, direnv only checks for changes.
    if [ "$PATH" != "''${AGENT_DIRENV_PATH-}" ]; then
      unset DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES NIX_DIRENV_DID_FALLBACK
    fi

    # BASH_ENV= stops direnv's own bash from sourcing this file again.
    eval "$(BASH_ENV= DIRENV_LOG_FORMAT= ${pkgs.direnv}/bin/direnv export bash)"
    export AGENT_DIRENV_PATH="$PATH"

    # nix-direnv keeps the previous devshell when evaluation fails, e.g. in
    # Codex's sandbox, which can't reach the nix daemon.
    if [ -n "''${NIX_DIRENV_DID_FALLBACK-}" ]; then
      echo "direnv: couldn't re-evaluate this project's devshell, so this command has the previous one. Run \`direnv exec . true\` outside the sandbox to rebuild it or see the error." >&2
    fi
  '';

  # Codex removes BASH_ENV from the environment of the commands it runs, even
  # when shell_environment_policy sets it. It runs them with whichever bash is
  # first on its PATH (NixOS-WSL's login shell is a `wrapper` binary it
  # doesn't recognise), so the codex wrapper puts this one first: it restores
  # BASH_ENV and execs the real bash. bashInteractive because Codex's shell
  # snapshot needs compgen.
  bash = pkgs.runCommand "agent-bash" {
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
  } ''
    makeBinaryWrapper ${pkgs.bashInteractive}/bin/bash $out/bin/bash \
      --set-default BASH_ENV ${loader}
  '';
}
