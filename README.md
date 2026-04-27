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
nix run home-manager/master -- switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix -b backup"
```

## Update
```shell
# For NixOS
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos

# For Ubuntu Standalone
home-manager switch --impure --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```
