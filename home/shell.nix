{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      # Auto-launch zsh for interactive sessions
      if [ -t 1 ] && [ -n "$BASH_VERSION" ] && [ "$0" = "-bash" -o "$0" = "bash" ]; then
        exec zsh -l
      fi
    '';
  };

  programs.zsh = {
    enable = true;
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
  };
}
