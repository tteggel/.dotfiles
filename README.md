# .dotfiles

A single minimal `seed.wsl` is published from every push to `master`. Importing it
gives you a tiny NixOS-WSL bootstrap that, on first interactive login, asks
which identity to take and `nixos-rebuild boot`s into it.

## Install (NixOS-WSL)

From Windows PowerShell:
```powershell
$tarball = "$env:USERPROFILE\Downloads\seed.wsl"
Invoke-WebRequest -Uri "https://github.com/tteggel/.dotfiles/releases/latest/download/seed.wsl" -OutFile $tarball
wsl --import thixos "$env:USERPROFILE\WSL\thixos" $tarball
wsl -d thixos
# → at the prompt, type `t` for thixos or `y` for yoloixos (YOLO to confirm)
# → seed stages the chosen config and terminates the distro
wsl -d thixos
# → boots into the chosen identity; init-gh / init-yolo completes setup
```

## Architecture

- `seed` — minimal bootstrap; bash login, NOPASSWD wheel sudo, `inputs.self`
  baked at `/etc/nixos`. Prompts t/y, runs `nixos-rebuild boot --flake
  /etc/nixos#<choice>`, marks `/var/lib/seed-bootstrap.done`, then
  `wsl.exe --terminate $WSL_DISTRO_NAME`.
- `thixos` — interactive dev. User `thom` (wheel), Tailscale, full toolchain.
- `yoloixos` — agent sandbox. User `agent` (no wheel), no interop, no
  automount, outbound firewall, 4GB / 200% CPU slice. **One-way: `agent` has
  no sudo, so the image can never be rebuilt.**

## Update

Inside thixos:
```shell
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos
```
(Inside yoloixos this is intentionally impossible.)

## Spawn a new WSL distro from inside thixos

Open the session-picker and press **Ctrl+Y** ("Create from seed"). It prompts
for a name, downloads the latest `seed.wsl` from GitHub Releases, runs
`wsl.exe --import`, and launches it — landing you back at the t/y prompt
inside the new distro. Locally-installed distros also show up in the
session-picker (`wsl/<name>`) for quick attach.

## Install (Ubuntu / Non-NixOS Standalone)

Just the home-manager profile, no system-level isolation:
```shell
sh <(curl -L https://nixos.org/nix/install) --daemon
echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
mkdir -p ~/.config/nix && echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
mkdir -p ~/src/github.com/tteggel
git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel/.dotfiles
MINIMAL_ENV=1 nix run home-manager/master -- switch --impure -b backup \
  --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
# then, once the binary cache has primed, the full env:
home-manager switch --impure -b backup --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```
Swap `thom@nix` for `agent@nix` to take the restricted agent profile (no
infrastructure tools; relies on shell-level discipline, not kernel
isolation).
