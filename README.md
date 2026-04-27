# .dotfiles

## Install (NixOS-WSL)
```shell
mkdir -p ~/src/github.com/tteggel && \
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel/.dotfiles && \
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos --option experimental-features 'nix-command flakes'"
```

## Install (Ubuntu / Non-NixOS Standalone)
Make sure Nix is installed on your system.
```shell
mkdir -p ~/src/github.com/tteggel && \
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel/.dotfiles && \
nix --extra-experimental-features 'nix-command flakes' run home-manager/master -- switch --flake ~/src/github.com/tteggel/.dotfiles#thom@nix"
```

## Update
```shell
# For NixOS
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos

# For Ubuntu Standalone
home-manager switch --flake ~/src/github.com/tteggel/.dotfiles#thom@nix
```
