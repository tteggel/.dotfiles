{ pkgs, servers }: let
  # Grok has no config-file flag, and its `GROK_CONFIG` overlay is allowlisted
  # to soft settings (`mcp_servers` is dropped at the choke point), so the
  # store-symlink slot is the managed layer: `~/.grok/managed_config.toml`
  # takes the same keys as config.toml and merges below it. Grok only ever
  # writes config.toml, so the read-only nix-store symlink survives Grok
  # rewriting its own settings, and a hand-edited config.toml still wins.
  managedConfig = (pkgs.formats.toml { }).generate "grok-managed-config.toml" {
    mcp_servers = servers;

    # Matches CLAUDE_CODE_EFFORT_LEVEL=max. Grok's canonical ladder is
    # none/minimal/low/medium/high/xhigh/max; a model that does not advertise
    # `max` falls back to the top level its own menu offers. This is the
    # default only -- `/effort` still overrides it for the session.
    models.default_reasoning_effort = "max";
  };
in {
  managedFiles = {
    ".grok/managed_config.toml".source = managedConfig;
  };
}
