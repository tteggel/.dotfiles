{ lib, ... }: let
  policy = import ../home/agent-permissions.nix { inherit lib; };
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

  # No /etc/github-copilot/managed-settings.json. Once a managed policy sets
  # any of deny, ask or allow, Copilot asks for every operation none of them
  # matches, even with deny alone. That routed every file read and git status
  # through the assisted-approval judge, ignored saved approvals and stopped
  # offering session-wide ones, so every doubt the judge had became a prompt
  # ("Organization policy requires confirmation"). The copilot launcher's
  # --deny-tool flags and the PAM-less SDK still block PAM.
  # https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference#managed-permission-rules
}
