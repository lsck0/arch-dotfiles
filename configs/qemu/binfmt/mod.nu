# Foreign architectures' binaries run under qemu user mode: the kernel hands an aarch64 (or other) ELF to the static
# qemu, so cross-built tests run and spawn children directly (nyangine's `./build run test --arm64`). The binfmt package
# registers every architecture with the F flag (the interpreter opened at registration, so it works inside sandboxes and
# containers); systemd's pacman hook loads it on install.
export const meta = {packages: {pacman: [qemu-user-static qemu-user-static-binfmt]}}
