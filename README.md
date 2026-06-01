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
  baked at `/etc/seed-source`. Prompts t/y, runs `nixos-rebuild switch --flake
  /etc/seed-source#<choice>` (switch, not boot — activation must rewrite
  `/etc/wsl.conf` *now* so the next launch finds the new default user), marks
  `/var/lib/seed-bootstrap.done`, then `wsl.exe --terminate $WSL_DISTRO_NAME`.
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

## Embedded debug probes (USB/IP passthrough)

`thixos` forwards a USB debug probe from Windows into WSL over USB/IP, so you can
flash/debug ARM/RISC-V targets (e.g. a Pico running `debugprobe` firmware wired to
a target Pico 2 / RP2350 over SWD). `nixos/embedded.nix` provides **only the USB
plumbing**: the `wsl.usbip` client, the `vhci_hcd` kernel module, an auto-attach
service, and a udev rule giving `thom` (via `plugdev`) non-root access to the probe.
**The toolchain (probe-rs etc.) lives in your project's devshell, not the system.**

### One-time setup

On Windows (admin PowerShell) — install the USB/IP daemon and share the probe:
```powershell
winget install usbipd
usbipd list                  # note the BUSID of your probe, e.g. 3-1
usbipd bind --busid <BUSID>  # plain bind — NOT --force (see Troubleshooting)
```
Set `autoAttach = [ "<BUSID>" ];` in `nixos/embedded.nix`, rebuild, then restart
WSL once (the restart loads `vhci_hcd` and applies the `plugdev` group):
```shell
sudo nixos-rebuild switch --flake ~/src/github.com/tteggel/.dotfiles#thixos
```
```powershell
wsl --shutdown               # from Windows; reopen thixos afterwards
```

### Day-to-day (hands-off)

Nothing — a systemd service (`usbip-auto-attach@<BUSID>`) polls every second and
(re)attaches the probe across boots, replugs and resets. Confirm with `lsusb`
(probe shows up, e.g. `2e8a:000c`). Manual override: `usbip-attach [VID:PID]`.

### The toolchain (in your project, not the dotfiles)

probe-rs is intentionally not system-installed — add it to the project devshell:
```nix
devShells.default = pkgs.mkShell {
  packages = [ pkgs.probe-rs-tools /* + rust toolchain, flip-link, … */ ];
};
```
Then `probe-rs list` sees the probe (via the system udev rule) and you flash with
`probe-rs run --chip RP235x <elf>` (`probe-rs chip list | grep -i rp235` for the
exact chip name).

### Troubleshooting (lessons learned)

- **Never `usbipd bind --force`.** It permanently swaps the device onto usbipd's
  VBoxUSB stub driver; it then flip-flops ("Shared (forced)" toggling) and the WSL
  attach alternates *"Device in error state"/"not found"*. Use plain `bind`. To
  recover a stuck device: Device Manager → Uninstall device → unplug/replug, then
  plain `bind`. If plain `bind` won't hold, a USB filter driver (real VirtualBox, or
  RDP/AV USB redirection) is claiming it — remove that.
- **Not in `lsusb`, `usbip port` says "is vhci_hcd loaded?"** → the module didn't
  load. It's `boot.kernelModules = [ "vhci_hcd" ]`; needs a `wsl --shutdown` (or
  `sudo modprobe vhci_hcd` to load immediately).
- **Can't reach the server** (`usbip list -r 127.0.0.1` fails) → Windows Firewall
  rule for TCP 3240. `snippetIpAddress = "127.0.0.1"` assumes mirrored networking
  (which `config/wslconfig` sets); NAT mode uses the eth0 gateway instead.
- No custom kernel is built — USB/IP rides the stock WSL2 kernel. *"WSL kernel is
  not USBIP capable"* → `wsl --update`.
- **Same port**: `bind`/`autoAttach` key on the physical port (busid); a different
  port needs a one-time `bind` + `autoAttach` update.

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
