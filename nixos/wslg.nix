{ ... }: {
  # WSLg GUI apps (Obsidian, and anything else with a window) render nothing —
  # a taskbar entry, a blank surface, and "[WARN:COPY MODE]" in the title —
  # unless /mnt/shared_memory exists. Weston allocates every client's frame
  # buffer under $WSL2_SHARED_MEMORY_MOUNT_POINT (that path); with the mount
  # absent it drops to a copy path that never paints. Symptom in
  # /mnt/wslg/weston.log:
  #   rdp_allocate_shared_memory: Failed to open "/mnt/shared_memory/{guid}"
  #   with error: Input/output error
  #
  # WSL stopped creating the mount itself in 2.7.3 and still doesn't as of
  # 2.7.10 — https://github.com/microsoft/wslg/issues/1456. It has to be
  # re-established on every boot; the "mount once and it sticks" claim in that
  # thread does not hold on current builds.
  #
  # Upstream's workaround is an /etc/fstab entry plus automount.mountFsTab, but
  # NixOS-WSL leaves mountFsTab off on purpose and lets systemd own fstab, so
  # the mount goes here: local-fs.target brings it up long before any GUI app
  # asks for a surface. systemd treats an already-mounted path as an active
  # mount unit, so this stays inert rather than shadowing WSL's own mount if
  # the bug gets fixed — but drop the module once it does.
  fileSystems."/mnt/shared_memory" = {
    device = "tmpfs";
    fsType = "tmpfs";
    # Unprivileged clients create their buffers here, same as /dev/shm.
    options = [ "mode=1777" ];
  };
}
