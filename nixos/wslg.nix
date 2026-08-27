{ ... }: {
  # WSLg GUI apps (Obsidian, and anything else with a window) render nothing —
  # a taskbar entry, a blank surface, and "[WARN:COPY MODE]" in the title —
  # unless /mnt/shared_memory exists. Weston negotiates the shared frame-buffer
  # pool named by $WSL2_SHARED_MEMORY_MOUNT_POINT (that path) once at WSLg
  # startup, and with the mount absent it falls back to a copy path that never
  # paints. Symptom, in /mnt/wslg/weston.log right after the env dump:
  #   rdp_allocate_shared_memory: Failed to open "/mnt/shared_memory/{guid}"
  #   with error: Input/output error
  #
  # WSL stopped creating the mount itself in 2.7.3 and still doesn't as of
  # 2.7.10 — https://github.com/microsoft/wslg/issues/1456. It has to be
  # re-established on every boot; the "mount once and it sticks" claim early in
  # that thread does not hold on current builds.
  #
  # thixos-only: yoloixos and seed are headless.
  fileSystems."/mnt/shared_memory" = {
    device = "tmpfs";
    fsType = "tmpfs";
    # Unprivileged clients allocate their buffers here, so 1777 — and
    # nosuid,nodev to match /dev/shm, since nothing here is ever a frame buffer.
    options = [ "mode=1777" "nosuid" "nodev" ];
  };

  # NixOS-WSL leaves mountFsTab off on the reasoning that systemd will mount
  # fstab entries for you, and normally that's right. Here it isn't: weston
  # runs in the WSLg *system* distro and does the handshake above as the VM
  # comes up, so a mount that waits for this distro's local-fs.target can lose
  # the race. WSL's own init reads fstab well before systemd starts, which is
  # what the workaround in the issue thread relies on. Turning it on costs
  # nothing — `fileSystems` above is the only entry NixOS-WSL puts in fstab, so
  # there is nothing else for WSL to mount early — and the systemd unit stays
  # as the backstop, a no-op when WSL got there first.
  #
  # (The mount point itself is a plain directory on the root filesystem; the
  # systemd unit creates it, so WSL's earlier pass finds it from then on.)
  wsl.wslConf.automount.mountFsTab = true;
}
