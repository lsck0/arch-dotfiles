# qemu

- `libvirt`: the guest network avoids 192.168.122.0/24 so nesting works.
- `waydroid`: images, init, container and `persist.waydroid.*` props are system layer.
- Guest storage and images are not backed up. The VM test is the `l-dotfiles-vm-test` skill.
