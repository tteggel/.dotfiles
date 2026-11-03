{ lib, agentDirenv, mcp, agentPermissions }: let
  # Guidance for the assisted-approval judge, Copilot's counterpart to the
  # autoMode environment in config/claude/settings.json. Left to itself the
  # judge narrows approval to the literal request: in October's sessions it
  # wanted confirmation for about three in ten reviewed actions, builds, tests
  # and commits among them, and autopilot cannot ask, so each one became a
  # denial the agent had to work around. Confirmation stays for anything Live,
  # outward-facing or destructive. No project IDs: this repository is public.
  #
  # On 2 November the judge still wanted confirmation for about one tool call
  # in five. Its reasons: an opinion question ("wdyt of the review comments")
  # doesn't cover editing, piping test output through tail masks the exit
  # status, a one-time approval was "spent", read-only inspection of a
  # non-default project, a local rootless Docker build with registry secrets,
  # and clean-up in Copilot's own session directory. The user approved every
  # one of them.
  #
  # By 3 November nearly every remaining prompt was a BigQuery read of the
  # Live project, for three reasons. The judge treated each Yes as spent once
  # the command ran ("the one-time approval was already used"), so a run of
  # analysis queries asked at every step. It read its own earlier verdicts,
  # which the runtime records as denied-interactively-by-user, as the user's
  # refusal ("earlier permission-prompt denial covers this query"). And it
  # could not see SQL kept in files (agentInstructions below). In the one
  # session running the 2 November text, the judge passed all 73 inline
  # queries against Live and stopped only the ones whose SQL it couldn't read.
  approvalInstructions = ''
    The user runs Copilot in autopilot on their own repositories and expects
    routine development steps to go ahead without confirmation. Judge an
    action by whether it is a reasonable step toward the task, including the
    investigation, verification and follow-up the task implies, not by
    whether the request named it. Don't ask because an action looks
    tangential or more thorough than strictly needed; ask only for the risks
    listed under "Ask first".

    A question about work in the repository, such as "wdyt of the review
    comments" or "what's wrong with this test", also delegates the follow-up:
    making, testing and committing the changes the agent concludes are needed
    is in scope.

    Earlier decisions in this session:
    - A Yes at a permission prompt approves that kind of action for the rest
      of the task, not only the invocation it answered: the same tool and
      subcommand on the same project, repository or dataset, with no wider
      effect. Repeats, reruns and changed filters or columns are covered, and
      so is raising the byte cap or row limit of an approved read-only query
      while a cap stays set. An approval to read never covers a write.
    - An approval the user types counts the same way, such as "read-only
      queries against the analytics project are fine for this task", and
      covers what it names until the task ends or the user narrows it.
    - Settlement records whose source is assisted_approval are your own
      earlier assessments, even when their result reads
      denied-interactively-by-user. They are not the user's refusal and never
      bind a later decision. Only a human_response denial does.

    Routine, approve:
    - Reading, searching and editing files in any repository under ~/src.
      Work often spans several sibling repositories in the same GitHub
      organization; changing one the task depends on is normal.
    - Building, testing, linting, formatting and type-checking: node, npm,
      npx, pnpm, yarn, mocha, tsc, biome, turbo, playwright, python, make,
      nix, direnv, including piping their output through tail, head or grep.
    - Local containers: starting a rootless Docker daemon (docker-daemon,
      rootlesskit, dockerd --rootless, unshare), docker build and run, build
      secrets from the user's own package-registry credentials, refreshing
      those with the repository's login script, and --no-sandbox for headless
      Chrome inside a container.
    - Local git: status, diff, log, show, branch, switch, checkout, worktree,
      stash, add, commit, rebase, and pushing branches other than the
      default branch.
    - Read-only gh (api GET requests; pr, issue and run view and list), and
      creating or updating pull requests.
    - Read-only gcloud, kubectl and bq in any project: list, describe, logs,
      metrics, serial port output, bq ls and bq show, query dry runs
      (--dry_run reads no data) and Test-environment queries. The gcloud
      default project is the Test environment.
    - Fetching public web pages and data: documentation, package indexes,
      release notes and security advisories.
    - Scratch files, including recursive deletes, in the repository, under
      /tmp and in Copilot's own session directory (~/.copilot/session-state).

    Ask first:
    - Reading user data or secrets in any project, cluster, namespace or
      database whose name suggests Live or production: queries, exports and
      database reads. Only the first read of a kind needs the user; see
      "Earlier decisions".
    - Changes to cloud resources, deploys, releases, publishing packages,
      and submitting Cloud Build builds or running triggers.
    - Pushing to main or master, force-pushing, deleting branches or tags,
      and rewriting published history.
    - Deleting data, recursive deletes anywhere else, and changes to IAM,
      secrets or credentials.
    - Sending repository contents or credentials anywhere other than the
      service they belong to.
  '';

  # User-level custom instructions (~/.copilot/copilot-instructions.md), read
  # alongside each repository's AGENTS.md. The judge sees the command text
  # and the conversation but not the files a command reads, so a query run
  # from a .sql file or a helper script left it unable to tell a read from a
  # write, and it escalated every one.
  agentInstructions = ''
    # Assisted permissions

    A permission judge reviews most tool calls before they run. It sees the
    command and the conversation, not the contents of files the command
    reads, so a step it cannot read becomes a prompt for the user, and in
    autopilot a denial. Keep what a command does visible in the command:

    - Pass SQL inline on stdin with a quoted heredoc, for example
      `bq query --use_legacy_sql=false --maximum_bytes_billed=N <<'SQL'`,
      never `< query.sql` or a helper script that builds or runs the query.
      The same goes for psql and other database clients.
    - Run one-off code inline as `python3 - <<'EOF'` or `node - <<'EOF'`
      rather than writing a script file and running it, at least whenever it
      queries, calls the network or writes outside the repository.
    - Dry-run BigQuery queries first and always set `--maximum_bytes_billed`.
    - Check credential files such as `.npmrc`, `.env` and key files for
      presence or non-secret keys only (`grep -c _authToken .npmrc`,
      `npm config get registry`). Never print them, even filtered.
    - Don't add `[skip ci]`, `--no-verify` or similar unless the user asks.
      The judge escalates skipped checks even after an approval.
    - When the judge stops a step, make its effect visible and try that
      instead of repeating the same command.
  '';

  # Written with `copilot config` on every activation, so these win over
  # changes made in /settings until the next rebuild. Copilot writes
  # settings.json itself, so it has to stay a real file. A running Copilot
  # keeps the judge instructions it started with: one started before the
  # 2 November rebuild was still judging by the old text the next morning.
  # Restart Copilot panes (copilot --continue) after changing them.
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
    # Hides model reasoning in the timeline; Ctrl+T toggles it for now. A
    # string because escapeShellArg turns a Nix false into ''.
    showReasoning = "false";
    # Groups tool calls and their approvals into expandable work summaries.
    transcriptView = "concise";
    assistedApprovalInstructions = approvalInstructions;
  };

  # Keys `copilot config` refuses ("Edit settings.json directly"), deep-merged
  # into settings.json after the settings above, keeping Copilot's own keys.
  jsonSettings = {
    # Lets Copilot consult the rubber-duck subagent for a second opinion
    # without being asked: /subagents, rubber-duck, Proactive invocation.
    subagents.agents.rubber-duck.autoInvoke = true;
  };
in {
  inherit approvalInstructions agentInstructions settings jsonSettings;

  # Activation script body. Copilot keeps settings.json at mode 0600, so the
  # merge stages under umask 077 and rewrites the file in place.
  settingsSeed = { copilot, jq }: ''
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (key: value: "${copilot} config ${key} ${lib.escapeShellArg value} >/dev/null || true")
      settings)}
    copilotSettings="''${COPILOT_HOME:-$HOME/.copilot}/settings.json"
    if [ -f "$copilotSettings" ] \
      && (umask 077; ${jq} --argjson pins ${lib.escapeShellArg (builtins.toJSON jsonSettings)} \
        '. * $pins' "$copilotSettings" > "$copilotSettings.new"); then
      cat "$copilotSettings.new" > "$copilotSettings"
    fi
    rm -f "$copilotSettings.new"
  '';

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
