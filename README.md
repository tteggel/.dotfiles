# .dotfiles

## Install (NixOS-WSL)
```shell
mkdir -p ~/src/github.com/tteggel && \
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel/.dotfiles && \
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos --option experimental-features 'nix-command flakes'"
```

## Install (Ubuntu / Non-NixOS Standalone)
Make sure Nix is installed on your system. If using the multi-user Nix daemon, you'll need to add yourself as a trusted user to allow binary caches:
```shell
echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
```

Then configure user-specific Nix settings and clone the repo:
```shell
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
mkdir -p ~/src/github.com/tteggel && \
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel/.dotfiles && \
MINIMAL_ENV=1 nix run home-manager/master -- switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix -b backup"
```

If you used the minimal install, run the full install afterwards to build out the full environment (which will now pull instantly from the binary cache!):
```shell
nix run github:nix-community/home-manager -- switch --impure -b backup --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```

## Update
```shell
# For NixOS
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos

# For Ubuntu Standalone
nix run github:nix-community/home-manager -- switch --impure -b backup --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```

## YOLO Mode (Autonomous Agents)
We provide a restricted sandbox environment designed specifically for running autonomous coding agents safely.

### On NixOS-WSL (True Isolation)
The `yoloixos` environment is a completely separate WSL distro with no `C:\` mounts, strict memory/CPU caps, and outbound network firewall rules (blocking cloud metadata and local subnets).

1. Build the locked-down tarball:
   ```shell
   nix build .#nixosConfigurations.yoloixos.config.system.build.tarballBuilder
   ```
2. Import it as a new WSL machine (run from Windows PowerShell or Linux via interop):
   ```shell
   wsl --import yoloixos .\yoloixos .\result\tarball\nixos-wsl-x86_64-linux.tar.gz
   ```
3. Boot into it directly or use `Alt+L` in WezTerm to launch the `WSL:yoloixos` domain!

### On Standalone Ubuntu (Profile Switching)
If you are running on a raw Ubuntu machine where we cannot enforce WSL boundaries, you can still switch your user profile to the restricted `agent` tooling profile. 
*(Note: This restricts installed packages, aliases, and removes infrastructure tools, but it does **not** enforce system-level firewalls or RAM limits).*

To migrate your current standalone user to the YOLO profile:
```shell
nix run github:nix-community/home-manager -- switch --impure -b backup --flake ~/src/github.com/tteggel/.dotfiles#agent@nix
```
To migrate back to the full developer environment:
```shell
nix run github:nix-community/home-manager -- switch --impure -b backup --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```
