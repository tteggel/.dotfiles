{ lib, grok, servers }: let
  # Grok's counterpart to CLAUDE_CODE_EFFORT_LEVEL=max. The canonical ladder is
  # none/minimal/low/medium/high/xhigh/max; a model that does not advertise
  # `max` falls back to the top level its own menu offers.
  reasoningEffort = "max";

  # Grok's counterpart to Claude's `autoCompactWindow` and Codex's
  # `model_auto_compact_token_limit`, both set to 256k tokens. Grok only takes a
  # percentage of the model's context window, so 256k is expressed against it:
  # grok-4.6's catalog entry is a 500k window (and an 80% default threshold), so
  # 51% is ~255k tokens. Revisit if the default model's window changes.
  #
  # The config key is `[session] auto_compact_threshold_percent`, and `session`
  # is not on the GROK_CONFIG allowlist (models, features, a narrowed toolset,
  # and shell_environment_policy filters), so the GROK_CONFIG overlay below
  # cannot carry it, and there is no `grok config set` to seed config.toml with
  # either. That leaves the env var GROK_AUTO_COMPACT_THRESHOLD_PERCENT -- read
  # by the same config resolver, clamped to 0..=100 -- as the durable slot.
  # Exported alongside GROK_CONFIG in home/home.nix and home/agent.nix.
  autoCompactThresholdPercent = 51;
in {
  inherit autoCompactThresholdPercent;

  # GROK_CONFIG is a config overlay layered above ~/.grok/config.toml, and
  # `models` is on its allowlist. An env var is also the one slot Grok cannot
  # rewrite -- see the note on mcpSeed below.
  envOverlay = builtins.toJSON { models.default_reasoning_effort = reasoningEffort; };

  # `~/.grok/managed_config.toml` looks like the declarative slot -- it takes
  # the same keys as config.toml and Grok never writes it during a session --
  # but any run that refreshes the model catalog deletes it outright
  # (reproducible: `grok models` removes the file). A home.file symlink there
  # survives only until the first such run. `mcp_servers` cannot move to the
  # GROK_CONFIG overlay either: the allowlist drops that table at the choke
  # point, since it can spawn commands.
  #
  # That leaves Grok's own config.toml, seeded through the CLI. `mcp add` is
  # "add or update", so re-running it is idempotent, and it rewrites only its
  # own table -- the marketplace and hint blocks Grok maintains are preserved.
  #
  # (On NixOS alone, `environment.etc."grok/managed_config.toml"` is read as
  # "System Managed" and is immune, being root-owned and outside $GROK_HOME.
  # It is not used here so that NixOS and standalone home-manager share one
  # mechanism.)
  mcpSeed = lib.concatMapStringsSep "\n" (name: let
    srv = servers.${name};
    args = lib.concatMapStringsSep " " lib.escapeShellArg srv.args;
  in "${grok}/bin/grok mcp add ${lib.escapeShellArg name} ${lib.escapeShellArg srv.command} -- ${args} >/dev/null || true")
    (builtins.attrNames servers);
}
