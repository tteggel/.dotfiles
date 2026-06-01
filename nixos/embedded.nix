{ pkgs, ... }: {
  # USB passthrough for embedded debug probes: forward a CMSIS-DAP probe (e.g. a
  # Pico running debugprobe firmware, wired to a target Pico 2 / RP2350 over SWD)
  # from Windows into WSL via USB/IP, and grant non-root access to it. The probe-rs
  # toolchain itself lives in the *project's* devshell, not the system — this module
  # is only the USB plumbing. thixos-only (absent from the yoloixos sandbox + seed).

  wsl.usbip = {
    # NixOS-WSL's native USB/IP plumbing: linuxPackages.usbip + udev + the
    # auto-attach loop. No custom kernel — the stock WSL2 kernel ships USB/IP.
    enable = true;

    # Hands-off attach: a systemd service polls every 1s and (re)attaches this
    # busid across boots, replugs and resets — no per-session Windows command.
    # busid is the *physical USB port*: rediscover with `usbipd list` (and
    # re-run `usbipd bind`) if the probe ever moves to a different port.
    autoAttach = [ "3-1" ];

    # Mirrored networking (config/wslconfig) ⇒ the Windows usbipd server is on
    # localhost. (The module default extracts the eth0 gateway, for NAT mode.)
    snippetIpAddress = "127.0.0.1";
  };

  # The Microsoft WSL2 kernel ships USB/IP as modules (CONFIG_USBIP_VHCI_HCD=m)
  # but doesn't load them at boot — and wsl.usbip's autoAttach loop assumes
  # vhci_hcd is already up (it polls /sys/devices/platform/vhci_hcd.0/status).
  # Load it at boot so /sys/bus/usb and the vhci device exist; modprobe pulls in
  # usbip-core. Takes effect after a `wsl --shutdown` (module loads at boot).
  boot.kernelModules = [ "vhci_hcd" ];

  environment.systemPackages = [
    pkgs.usbutils                       # lsusb, to confirm the device attached
    (pkgs.writeShellApplication {       # manual fallback / ad-hoc or new port
      name = "usbip-attach";
      text = builtins.readFile ../scripts/usbip-attach.sh;
    })
  ];

  # Grant non-root access to the probe once usbip attaches it, so probe-rs (in
  # the *project* devshell, not here) can open it as thom. Inline rather than
  # pulling in probe-rs-tools just for its udev rules.
  services.udev.extraRules = ''
    # Raspberry Pi Debug Probe / Pico running debugprobe firmware (CMSIS-DAP):
    SUBSYSTEM=="usb", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="000c", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    # Any CMSIS-DAP probe:
    SUBSYSTEM=="usb", ATTRS{product}=="*CMSIS-DAP*", MODE="0660", GROUP="plugdev", TAG+="uaccess"
  '';

  # The udev rules above grant the "plugdev" group, which NixOS doesn't define by
  # default. Create it and add thom. (uaccess is unreliable in WSL's session-less
  # environment, so group membership is the dependable path; extraGroups merges
  # with the "wheel" set in configuration.nix.)
  users.groups.plugdev = {};
  users.users.thom.extraGroups = [ "plugdev" ];
}
