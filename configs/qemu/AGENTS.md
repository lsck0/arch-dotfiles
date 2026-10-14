# qemu

Extends the root `AGENTS.md`. Virtualization and Android emulation.

## Modules

- `libvirt`: libvirt/qemu with a non-default guest network (avoids the 192.168.122.0/24 collision when nested).
- `waydroid`: the Android container; images, init, container and `persist.waydroid.*` props are the system layer.
- `containers`: distrobox on rootless podman (packages only).

## Conventions

- Guest storage and images are re-downloadable or rebuildable and excluded from borg (see root backup model).
- The VM test harness (`dot test run`) drives libvirt end to end; see the `l-dotfiles-vm-test` skill, not this group.
