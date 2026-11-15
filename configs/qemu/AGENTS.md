# qemu

- `libvirt`: the default NAT network (192.168.122.0/24) stays off when that subnet is already routed (a nested guest).
  `qemu:///system` asks for the key per client process: several commands go in one `virsh -c qemu:///system` shell;
  everything else uses `qemu:///session`.
- `waydroid`: images, init, container and `persist.waydroid.*` props are system layer.
- Guest storage and images are not backed up. The VM test is the `l-dotfiles-vm-test` skill.
