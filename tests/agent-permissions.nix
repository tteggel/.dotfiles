{ pkgs, codex, managedFiles }: let
  policy = import ../home/agent-permissions.nix { inherit (pkgs) lib; };
  sdk = import ../home/google-cloud-sdk.nix { inherit pkgs; };
  fixture = pkgs.writeText "agent-permissions.json" (builtins.toJSON {
    inherit policy;
    managedFiles = builtins.mapAttrs (_: file: {
      inherit (file) text mode user group;
    }) (pkgs.lib.filterAttrs (name: _: builtins.elem name [
      "codex/requirements.toml"
      "claude-code/managed-settings.json"
      "github-copilot/managed-settings.json"
    ]) managedFiles);
  });
in pkgs.runCommand "agent-permissions-check" {
  nativeBuildInputs = [ pkgs.python3 codex ];
} ''
  python3 ${./agent-permissions.py} ${fixture} ${sdk}
  touch "$out"
''
