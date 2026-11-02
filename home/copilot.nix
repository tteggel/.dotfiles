{ lib, agentDirenv, mcp, agentPermissions }: let
  # Guidance for the assisted-approval judge, Copilot's counterpart to the
  # autoMode environment in config/claude/settings.json. Left to itself the
  # judge narrows approval to the literal request: in October's sessions it
  # wanted confirmation for about three in ten reviewed actions, builds, tests
  # and commits among them, and autopilot cannot ask, so each one became a
  # denial the agent had to work around. Confirmation stays for anything Live,
  # outward-facing or destructive. No project IDs: this repository is public.
  approvalInstructions = ''
    The user runs Copilot in autopilot on their own repositories and expects
    routine development steps to go ahead without confirmation. Judge an
    action by whether it is a reasonable step toward the task, including the
    investigation, verification and follow-up the task implies, not by
    whether the request named it.

    Routine, approve:
    - Reading, searching and editing files in any repository under ~/src.
      Work often spans several sibling repositories in the same GitHub
      organization; changing one the task depends on is normal.
    - Building, testing, linting, formatting and type-checking: node, npm,
      npx, pnpm, tsc, biome, turbo, playwright, python, make, nix, direnv.
    - Local git: status, diff, log, show, branch, switch, checkout, worktree,
      stash, add, commit, rebase, and pushing branches other than the
      default branch.
    - Read-only gh (api GET requests; pr, issue and run view and list), and
      creating or updating pull requests.
    - Read-only gcloud, kubectl and bq in the gcloud default project, which
      is the Test environment.
    - Scratch files in the repository and under /tmp.

    Ask first:
    - Anything in a Google Cloud project other than the default, and any
      project, cluster, namespace or database whose name suggests Live or
      production.
    - Changes to cloud resources, deploys, releases, publishing packages,
      and submitting Cloud Build builds or running triggers.
    - Pushing to main or master, force-pushing, deleting branches or tags,
      and rewriting published history.
    - Deleting data, recursive deletes outside the repository and /tmp, and
      changes to IAM, secrets or credentials.
    - Sending repository contents or credentials to third-party services.
  '';

  # Written with `copilot config` on every activation, so these win over
  # changes made in /settings until the next rebuild. Copilot writes
  # settings.json itself, so it has to stay a real file.
  settings = {
    # An interactive session refuses --assisted-approval ("only supported in
    # non-interactive prompt mode or direct workflow mode").
    defaultPermissionMode = "assisted";
    # The default effort wherever no --reasoning-effort applies. Sessions
    # started with /new or /clear inside a running pane ignore the launch
    # flags, and two Opus sessions ran at medium that way, a level left over
    # from /model.
    effortLevel = "xhigh";
    # Lets BASH_ENV through to Copilot's shells, for the wrapper's direnv
    # loader.
    bashEnv = "on";
    assistedApprovalInstructions = approvalInstructions;
  };
in {
  inherit approvalInstructions settings;

  settingsSeed = copilot: lib.concatStringsSep "\n" (lib.mapAttrsToList
    (key: value: "${copilot} config ${key} ${lib.escapeShellArg value} >/dev/null || true")
    settings);

  # Body of the copilot wrapper in home/home.nix and home/agent.nix.
  #
  # Explicit denies win over repo approvals, assisted mode and --allow-all
  # wherever they appear, so they go before "$@" with the other defaults.
  # After it they land inside subcommands: `copilot mcp list` rejects them and
  # `copilot mcp add ... --` stores them as the server's own arguments.
  #
  # BASH_ENV: Copilot's session shell sources the direnv loader when it
  # starts (bashEnv above), so commands get the devshell of the directory
  # Copilot started in, as Claude's and Codex's do.
  # --add-dir: Copilot limits file access to the working directory, where
  # Claude and Codex read across repositories.
  wrapperText = ''
    export BASH_ENV=${agentDirenv.loader}
    args=(--additional-mcp-config=@${mcp.copilotMcpConfig})
    if [ -d "$HOME/src" ]; then args+=("--add-dir=$HOME/src"); fi
    exec copilot ${agentPermissions.copilotArgs} "''${args[@]}" "$@"
  '';
}
