<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

Boot the Arch ISO, enable Secure Boot Setup Mode in the firmware, get online (`iwctl` for wifi), then

```bash
curl -fsSL https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh | bash -s -- luca-pc
```

with the platform from `platforms/` (`luca-pc`, `luca-notebook`). It asks for one password (LUKS and user), wipes the only disk and installs a minimal system (LUKS2, btrfs subvolumes for timeshift, GRUB). The next two boots run by themselves, `install.sh` (packages) and then `config.sh` (links), chained by `stage.sh`: the disk unlocks with a temporary keyfile and sudo asks nothing until the chain ends, which removes both and reboots into the normal prompts. Secure Boot keys get enrolled on the way. Failures end up in `/var/lib/dotfiles-stage/log` and `FAILURES.*`; rerun the script in question by hand.

The platform file decides package groups, boot features and which prebuilt packages to take. On an existing system `./install.sh`, reboot, `./config.sh` does the same by hand.

Everything that would compile locally (see `mirror/packages.conf`) comes prebuilt as `lsck0-<name>` from `https://mirror.lsck0.dev`, built nightly by the homelab; a failed build keeps the previous package. `MIRROR_SKIP` in a platform file builds an entry locally instead.

`./test` runs the whole chain in a fresh libvirt VM (needs the `libvirt` group) from `~/downloads/archlinux-x86_64.iso` (config in `vm-test/`), tests the local working tree (bundled on top of `origin/master`; `--master` tests github master instead) and exits non-zero on failures. Logs land in `~/.cache/vm-test/`.

## Things to do manually after rebooting

- add fingerprint with `fprintd-enroll` (from fprintd-clients, pulled in by python-validity-git; once per device, persistent across reinstalls)

- log into spotify, discord and steam once; user path units apply spicetify, betterdiscord and millennium afterwards

- run `install-unreal` once syncthing has put its zip into `~/sync` (jai installs itself from there)

- fetch the submodules (needs github auth, do `gh auth login`)

```bash
git submodule update --init --recursive
```

- decrypt the secrets submodule (git-crypt). Import the PGP key `E7501F533316E9AFC6AAE907122F2CB527D1EFE3` from your own backup first (it is not in the repo), then unlock.

```bash
gpg --import /path/to/gpg-private-key.asc
( cd ~/projects/arch-dotfiles/configs/secrets && git-crypt unlock )
```

- give another GPG key access to the secrets (from an unlocked checkout, e.g. for a new machine)

```bash
( cd ~/projects/arch-dotfiles/configs/secrets && git-crypt add-gpg-user <fingerprint> && git push )
```

- set up ssh key from the (now decrypted) secrets submodule

```bash
sudo chmod 600 ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc
secret-tool store --label="ssh_privatekey passphrase" ssh-key ssh_privatekey
systemctl --user start ssh-add.service
```

- add wireguard vpn tunnel

```bash
sudo ln -sf ~/projects/arch-dotfiles/configs/secrets/wg0.<platform>.conf /etc/wireguard/wg0.conf
```

## Screenshots

Amazing wallpapers: https://aenamiart.artstation.com/

![screenshot](https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/showcase/showcase1.png)
