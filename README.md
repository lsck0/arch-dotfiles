<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

Easiest: write [Arch Linux-LSCK0](https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso)
([sha256](https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso.sha256),
[sig](https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso.sig) by
`88042EFBF5F141C2ACF4697ADD84D7C4053DD354`, `configs/base/pacman/archrepo.asc`) to a stick and boot it; the installer
starts on its own (an answer file skips its questions: `mirror/iso/lsck0.example.nuon`).

Or from the official Arch ISO:

```bash
curl -fsSL https://install-linux.lsck0.dev | sh
# same script, if that host is down:
curl -fsSL https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh | bash
```

UEFI only; the chosen disk is erased. Pick the `custom` profile unless you are me. Update later with `dot sync`.

You trust me with root: the install signs my package key into pacman, my `[lsck0]` repo is searched before the
official ones, and `dot sync` runs whatever I sign as root.

![bar with weather and network panels and a fastfetch terminal](showcase/showcase1.png)
![wallpaper picker](showcase/showcase2.png)
![app launcher](showcase/showcase3.png)
![clock and system panels](showcase/showcase4.png)
