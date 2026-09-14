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

For secure boot: disable while installing base system, enable before running install.sh.

## Things to do manually after rebooting

- add fingerprint with `fprintd-enroll` (once per device, persistent across reinstalls)

- tune LUKS for better performance

```bash
cryptsetup reencrypt \
  --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 256 \
  --sector-size 4096 \
  --pbkdf argon2id \
  /dev/nvme0n1p2
```

- run `spicetify backup apply && spicetify enable-devtools` after running spotify once (including logging in)

- run `betterdiscordctl install` after running discord once (including logging in)

- fetch the submodules (needs github auth, do `gh auth login`)

```bash
git submodule update --init --recursive
```

- import shh and pgp keys from secrets submodule

```bash
gpg --import ~/projects/arch-dotfiles/configs/secrets/pgp_privatekey.asc

sudo chmod 600 ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc
ssh-add ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc
```

- add wirguard vpn tunnel

```bash
sudo ln -sf ~/projects/arch-dotfiles/configs/secrets/wg0.laptop.conf /etc/wireguard/wg0.conf
```

## Currently Clanker Wanked and Not Reviewed

- Toggles
- Quickshell

## Screenshots

Amazing wallpapers: https://aenamiart.artstation.com/

![screenshot](https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/showcase/showcase1.png)
