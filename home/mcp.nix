{ pkgs, lib }: let
  servers = {
    chrome-devtools = {
      command = "npx";
      args = [
        "-y"
        "chrome-devtools-mcp@latest"
        "--browser-url=http://127.0.0.1:9222"
      ];
    };
  };

  claudeMcpConfig = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers = lib.mapAttrs (_: srv: { type = "stdio"; } // srv) servers;
  });

  # The shape `copilot mcp add` writes to ~/.copilot/mcp-config.json.
  copilotMcpConfig = pkgs.writeText "copilot-mcp.json" (builtins.toJSON {
    mcpServers = lib.mapAttrs (_: srv: { type = "local"; tools = [ "*" ]; } // srv) servers;
  });

  codexInline = srv: let
    jsonArr = xs: "[${lib.concatMapStringsSep "," builtins.toJSON xs}]";
  in "command=${builtins.toJSON srv.command},args=${jsonArr srv.args},startup_timeout_ms=60000";

  codexArgs = lib.mapAttrsToList
    (name: srv: "-c 'mcp_servers.${name}={${codexInline srv}}'")
    servers;

  agyExtensionFiles = lib.listToAttrs (lib.mapAttrsToList
    (name: srv: lib.nameValuePair
      ".gemini/extensions/${name}/gemini-extension.json"
      { text = builtins.toJSON { inherit name; version = "1.0.0"; mcpServers.${name} = srv; }; })
    servers);
in {
  inherit servers claudeMcpConfig copilotMcpConfig codexArgs agyExtensionFiles;
}
