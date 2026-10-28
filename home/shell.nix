{ config, pkgs, lib, ... }: {
  programs.helix = {
    enable = true;
    defaultEditor = true;
    # Match the One Dark palette used by Starship and Zellij.
    settings.theme = "onedark";
  };

  programs.git.settings.core.editor = "hx";

  programs.bash = {
    enable = true;
    initExtra = ''
      # Auto-launch zsh for interactive sessions
      if [ -t 1 ] && [ -n "$BASH_VERSION" ] && [ "$0" = "-bash" -o "$0" = "bash" ]; then
        exec zsh -l
      fi
    '';
  };

  # Consomme's localhost relay can't forward Node's default dual-stack [::]
  # listener (microsoft/WSL#41860), so dev servers that call listen(port) are
  # unreachable from Windows browsers. This preload makes them bind IPv4;
  # envExtra below loads it into every Node process.
  xdg.configFile."node/ipv4-listen.js".source = ../config/node/ipv4-listen.js;

  programs.zsh = {
    enable = true;
    # New Zellij panes inherit the session's original environment, including
    # Home Manager's guard against sourcing session variables again.
    envExtra = ''
      export EDITOR="${config.home.sessionVariables.EDITOR}"
      export VISUAL="${config.home.sessionVariables.VISUAL}"
      # Node refuses to start if a --require target is missing, so check first.
      if [ -r "$HOME/.config/node/ipv4-listen.js" ]; then
        case " ''${NODE_OPTIONS-} " in
          *ipv4-listen.js*) ;;
          *) export NODE_OPTIONS="--require=$HOME/.config/node/ipv4-listen.js''${NODE_OPTIONS:+ $NODE_OPTIONS}" ;;
        esac
      fi
    '';
    # Preserve the existing layout when home.stateVersion 26.05 changes the
    # default to $XDG_CONFIG_HOME/zsh.
    dotDir = config.home.homeDirectory;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history.size = 10000;
    history.path = "$HOME/.zsh_history";
    
    shellAliases = {
      ls = "eza";
      ll = "eza -l --git";
      la = "eza -la --git";
      lt = "eza -T --git-ignore";
      cat = "bat --paging=never";
      grep = "rg";
      find = "fd";
    };
    # Claude Code builds its Bash tool's shell from an interactive zsh, so it
    # would get these too and run eza, bat, rg and fd, which take different
    # flags, in place of ls, cat, grep and find. It sets CLAUDECODE in that
    # shell. Order 1500 runs after Home Manager defines the aliases (1100).
    initContent = lib.mkOrder 1500 ''
      if [[ -n ''${CLAUDECODE-} ]]; then
        unalias ${lib.concatStringsSep " " (builtins.attrNames config.programs.zsh.shellAliases)}
      fi
    '';
  };
}
