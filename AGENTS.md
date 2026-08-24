# .dotfiles

NixOS configuration for `thixos`, a WSL2-based development machine.

## Repository Structure

```
.dotfiles/
├── flake.nix              # Top-level flake: NixOS config + inputs
├── flake.lock
├── nixos/
│   └── configuration.nix  # System config (~700 lines, the core of everything)
├── config/
│   ├── zellij/            # Zellij config, layouts, plugin config
│   ├── starship.toml      # Shell prompt
│   └── windows-terminal.json # Terminal emulator (runs on Windows, copied via script)
├── bespoke/
│   └── zellij/
│       └── dim-unfocused/ # Custom Zellij build + shader plugin (has its own AGENTS.md)
├── templates/             # Nix flake templates
└── .zshrc, .gitconfig, etc.
```

## How It Builds

The top-level `flake.nix` produces a single NixOS configuration (`thixos`):

- **Inputs**: `nixpkgs` (unstable), `nixos-wsl`, `llm-agents` (Claude Code, Antigravity, Codex, Grok), `dim-unfocused` (local path flake for custom Zellij)
- **Output**: `nixosConfigurations.thixos`

The `dim-unfocused` sub-flake (at `bespoke/zellij/dim-unfocused/`) has its own inputs including a Zellij fork. It produces a custom Zellij binary and a WASM plugin. See `bespoke/zellij/dim-unfocused/AGENTS.md` for deep details on the shader system.

### Deploying changes

```bash
# For NixOS
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos

# For Standalone / Ubuntu
home-manager switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```

## configuration.nix and home.nix

This is the heart of the system. `nixos/configuration.nix` sets up OS-level features, while `home/home.nix` defines the user environment:

### Custom shell scripts (in home.nix)

The configuration embeds several substantial shell applications as `writeShellApplication` derivations:

- **`session-picker`** — Zellij session manager. Lists existing sessions, creates new ones, clones GitHub repos. Launched on shell login.
- **`command-palette`** — Context-aware fzf command launcher with ~25 commands. Invoked via Zellij keybinding.
- **`code-session`** — Open the code layout in Zellij (agents launch fresh; resume via each agent's own native picker).
- **`gcloud-switch`**, **`gcloud-reauth`** — GCP project/cluster switching.
- **`zed`** — Interop wrapper to launch Windows Zed editor from WSL.
- **`open-browser`** — Opens URLs in Windows Chrome from WSL.

### Shell environment (zsh)

- Starship prompt
- Auto-attaches to Zellij on login
- Zoxide + fzf for directory navigation
- Dynamic pane titles (`repo:branch` format via precmd/preexec hooks)
- Environment: `ZELLIJ_CONFIG_DIR`, `BROWSER`, `EDITOR` (micro), `MANPAGER` (bat)

### System packages

Dev tools (zellij, git, gh, ripgrep, fd, bat, eza, delta, lazygit, difftastic), cloud tools (gcloud, kubectl), LLM agents (claude-code, antigravity/agy, codex, grok).

### Config file management

Files from `config/` are symlinked into `~/.config/` via Home Manager's `xdg.configFile`. The Windows Terminal config is copied to the Windows filesystem via NixOS activation scripts (NixOS only).

## Working with this repo

- **Zellij is custom-built** from a fork with pane shader support. Don't update the `dim-unfocused` flake input without checking the fork is in sync. See `bespoke/zellij/dim-unfocused/AGENTS.md`.
- **Zellij rebuild takes ~20 minutes** (Rust). Avoid changes to the fork unless necessary. The plugin and shader WASM rebuild in seconds.
- **The `config/zellij/config.kdl`** loads the dim-unfocused plugin. If the plugin WASM path changes, update it there.
- **Shell scripts in `configuration.nix`** are the most frequently edited part. They rebuild instantly with `nswitch`.
- **Flake lock updates**: The top-level lock pins transitive inputs from sub-flakes. After updating `bespoke/zellij/dim-unfocused/flake.lock`, also run `nix flake update` at the top level to propagate.
