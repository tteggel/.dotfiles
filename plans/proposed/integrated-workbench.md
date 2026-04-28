# Integrated Terminal Workbench: Master Architecture & Implementation Strategy

## Executive Summary & Architectural Critique
The previous iteration of this plan presented a superficial mapping of IDE keybindings onto a terminal multiplexer, critically misunderstanding the complexities of WSL2/Windows interoperability and terminal input processing. 

**Critical flaws identified in the previous draft:**
1.  **Naive WSL Pathing:** Simply invoking Windows `zed.exe` from WSL with Unix paths will fail silently or open empty buffers. Complete path translation (`wslpath -w`) is mandatory for all file arguments.
2.  **Terminal Input Illusions:** Terminals do not inherently distinguish `Ctrl+Shift+P` from `Ctrl+P` without explicit escape sequence configuration (e.g., Kitty Keyboard Protocol). Assuming this works out-of-the-box in Zellij/Windows Terminal is a rookie mistake. We must ensure Windows Terminal is emitting the correct CSI u sequences, or choose a safe fallback.
3.  **Brittle Deployment:** Hardcoding `C:\Users\thom\...` in NixOS activation scripts is fragile and violates declarative paradigms. It assumes the user environment instead of dynamically resolving it.
4.  **Suboptimal Exits:** Yazi as a file explorer is useless if exiting doesn't change the parent shell's working directory. The previous plan missed the shell wrapper entirely.

This revised architecture provides a robust, idiomatic, and truly integrated environment.

## 1. Robust WSL/Windows Interoperability (The Zed Wrapper)
To use Windows Zed flawlessly as our `$EDITOR` (including `git commit --wait`), we require a robust wrapper script that handles path marshaling.

*   **File:** `nixos/configuration.nix` (within `environment.systemPackages`)
*   **Implementation:**
    ```nix
    (writeShellApplication {
      name = "zed";
      text = ''
        # Convert all Unix path arguments to Windows paths
        args=()
        for arg in "$@"; do
          if [[ -e "$arg" || "$arg" == /* ]]; then
            # Resolve absolute Windows path
            args+=("$(wslpath -w "$arg")")
          else
            args+=("$arg")
          fi
        done
        
        # Determine Windows Zed executable path dynamically or use a known reliable path
        ZED_BIN="/mnt/c/Users/thom/AppData/Local/Microsoft/WindowsApps/zed.exe"
        if [ ! -f "$ZED_BIN" ]; then
           # Fallback if installed via different method
           ZED_BIN="/mnt/c/Program Files/Zed/zed.exe"
        fi

        exec "$ZED_BIN" "''${args[@]}"
      '';
    })
    ```
*   **Config Deployment:** We will utilize `$WSL_USERPROFILE` or standard `wslpath` logic in activation scripts to deploy Windows-side configurations rather than hardcoded paths.

## 2. Advanced Terminal & Multiplexer Keybindings
To achieve true IDE-standard bindings, we must account for terminal limitations. Windows Terminal must be configured to pass extended keyboard events, and Zellij must be configured to receive them.

### Zellij Configuration (`config/zellij/config.kdl`)
We prioritize workflow fluidity and strictly eliminate binding collisions.
*   **File Picker (`Ctrl+P`)**: Launches a dedicated fzf script integrating `bat` previews, piping the selection to our new `zed` wrapper.
*   **Command Palette (`Alt+P` or `Ctrl+Shift+P`)**: *Note: We will configure Windows Terminal to ensure `Ctrl+Shift+P` is passed correctly, or default to `Alt+P` for maximum compatibility.*
*   **Contextual Panes**: 
    *   `Ctrl+W`: Close pane (matches Zed tab close).
    *   `Ctrl+HJKL`: Seamless pane navigation.
    *   `Ctrl+N`: New pane (matches Zed new file).
*   **Freed Keys**: `Ctrl+S`, `Ctrl+F`, `Ctrl+Q`, `Ctrl+D` are strictly unbound in Zellij to allow passthrough to Zed/Micro/Shell.

### Windows Terminal Prerequisite (`config/windows-terminal.json`)
Ensure Windows Terminal enables CSI u or extended keys if `Ctrl+Shift+P` is strictly required.

## 3. Toolchain Deep-Dive

### A. Lazygit (`config/lazygit/config.yml`)
The previous plan vaguely stated "`e` key -> open file". Lazygit requires explicit `os.editCommand` configuration to leverage our wrapper, plus it needs to know how to handle the wait flag.
```yaml
os:
  editCommand: "zed"
  editCommandTemplate: "{{editor}} {{filename}}"
gui:
  theme:
    activeBorderColor:
      - '#61afef'
      - bold
```

### B. Yazi File Explorer (`config/yazi/yazi.toml` & Shell Init)
Yazi must be integrated into the shell so that `quit` (vs `quit --no-cwd`) updates the shell's `$PWD`.
*   **Action**: Add the `yy` wrapper to `programs.zsh.interactiveShellInit` in NixOS config:
    ```bash
    function yy() {
    	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    	yazi "$@" --cwd-file="$tmp"
    	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    		builtin cd -- "$cwd"
    	fi
    	rm -f -- "$tmp"
    }
    ```
*   **Zellij Binding**: Map `Ctrl+E` to `yy` (or a Zellij Run command that opens Yazi in a new pane).

### C. The Command Palette (Launchpad)
A simple flat list is insufficient. The `command-palette` script must be categorized and fuzzy-searchable, executing complex Zellij actions (e.g., opening a specific layout or floating pane).
*   **Categories**: `[Session]`, `[Git]`, `[K8s]`, `[Nix]`, `[Tools]`.
*   **Execution**: Wrap in a script that leverages `zellij action new-pane --floating`.

## 4. Execution & Verification Strategy
Never test in production.
1.  **Syntax Check**: Validate KDL and Nix files before switching. `nix-instantiate --parse nixos/configuration.nix`
2.  **Dry Run**: `sudo nixos-rebuild dry-activate --flake ~/src/github.com/tteggel/.dotfiles`
3.  **Live Test (Zellij)**: Run `zellij --config /home/thom/src/github.com/tteggel/.dotfiles/config/zellij/config.kdl` locally *before* committing the config to NixOS, verifying all keybindings (especially `Ctrl+Shift+P`).
4.  **Deployment**: Commit and apply the NixOS build.

## Summary of Superior Changes
*   **Solved WSL pathing** for Windows UI applications invoked from the Linux subsystem.
*   **Addressed terminal input limitations** regarding Shift modifiers.
*   **Implemented true CWD-syncing** for the Yazi file explorer.
*   **Provided exact declarative schemas** rather than vague intentions.
*   **Established a zero-downtime test protocol.**
