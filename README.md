<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

Run

```bash
mkdir -p ~/projects
git clone https://github.com/lsck0/arch-dotfiles.git ~/projects/arch-dotfiles/
cd ~/projects/arch-dotfiles/
./install.sh
```

after archinstall minimal with btrfs+subvolumes+compression+LUKS and no applications (bluetooth, audio, etc) configured to setup the system.

For secure boot: Enable Secure Boot + Setup Mode before archinstall.

`./test` does all of the above in a fresh system libvirt VM (needs the `libvirt` group) from `~/downloads/archlinux-x86_64.iso` (config in `vm-test/`), clones master from github and exits non-zero if `install.sh` reports failures. Logs land in `~/.cache/vm-test/`.

## Things to do manually after rebooting

- add fingerprint with `fprintd-enroll` (once per device, persistent across reinstalls)

- tune LUKS for better performance

```bash
sudo cryptsetup reencrypt /dev/nvme0n1p2
  --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 256 \
  --sector-size 4096 \
  --pbkdf argon2id
```

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
