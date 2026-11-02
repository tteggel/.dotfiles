{ lib }: let
  # Keep stable and preview commands together in every agent's policy.
  commands = [ "gcloud pam" "gcloud alpha pam" "gcloud beta pam" ];
  tokens = map (lib.splitString " ") commands;
  shellRules = tool: lib.concatMap
    (command: [ "${tool}(${command})" "${tool}(${command} *)" ])
    commands;
in {
  claudeDeny = shellRules "Bash";
  copilotDeny = shellRules "Shell";
  copilotArgs = lib.concatMapStringsSep " "
    (command: lib.escapeShellArg "--deny-tool=shell(${command}:*)" + " "
      + lib.escapeShellArg "--deny-tool=shell(${command})")
    commands;

  # Most restrictive wins, even against a repository's matching allow rule.
  codexRules = lib.concatMapStringsSep "\n" (pattern: ''
    prefix_rule(
        pattern = ${builtins.toJSON pattern},
        decision = "forbidden",
        justification = "Google Cloud PAM commands are disabled on this machine.",
    )
  '') tokens;

  # /etc/codex/requirements.toml is enforced independently of user/repo config.
  codexRequirements = lib.concatMapStringsSep "\n" (pattern: ''
    [[rules.prefix_rules]]
    pattern = [${lib.concatMapStringsSep ", " (token: "{ token = ${builtins.toJSON token} }") pattern}]
    decision = "forbidden"
    justification = "Google Cloud PAM commands are disabled on this machine."
  '') tokens;
}
