# .dotfiles

## Install
```shell
mkdir -p ~/src/github.com/tteggel && \
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/src/github.com/tteggel && \
sudo nixos-rebuild switch --flake ~/nixos-config#thixos --option experimental-features 'nix-command flakes'"
```

## Update
```shell
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles`
```
