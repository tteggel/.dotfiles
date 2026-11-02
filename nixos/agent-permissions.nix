{ lib, ... }: let
  policy = import ../home/agent-permissions.nix { inherit lib; };
  # Copilot rejects symlinks, non-root ownership, and world-writable policy
  # files. Use real root-owned files for all three agents.
  managedFile = text: {
    inherit text;
    mode = "0444";
    user = "root";
    group = "root";
  };
in {
  # https://learn.chatgpt.com/docs/enterprise/managed-configuration
  environment.etc."codex/requirements.toml" = managedFile policy.codexRequirements;

  # https://code.claude.com/docs/en/managed-settings
  environment.etc."claude-code/managed-settings.json" = managedFile (builtins.toJSON {
    permissions = {
      deny = policy.claudeDeny;
      disableBypassPermissionsMode = "disable";
    };
  });

  # https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference
  environment.etc."github-copilot/managed-settings.json" = managedFile (builtins.toJSON {
    permissions.deny = policy.copilotDeny;
  });
}
