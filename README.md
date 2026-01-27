# .dotfiles

## Install
```shell
nix-shell -p git --run "git clone https://github.com/tteggel/.dotfiles.git ~/nixos-config && \
sudo nixos-rebuild switch --flake ~/nixos-config#thixos --option experimental-features 'nix-command flakes' && \
mkdir -p ~/src/github.com/tteggel && \
sudo mv /home/nixos/nixos-config ~/src/github.com/tteggel/.dotfiles && \
sudo chown -R thom:users ~/src/github.com/tteggel"
```

## Update
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles
