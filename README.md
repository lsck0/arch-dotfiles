<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

TODO:

- cleanup scripts / toggles
- add new showcases

Run

```bash
mkdir -p ~/projects
git clone https://github.com/lsck0/arch-dotfiles.git ~/projects/arch-dotfiles/
cd ~/projects/arch-dotfiles/
./install.sh
```

after archinstall minimal and no applications (bluetooth, audio, etc) configured to setup the system.

## Things to do manually after rebooting

- add fingerprint with `fprintd-enroll` (once per device, persistent across reinstalls)

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

## Screenshots

Amazing wallpapers: https://aenamiart.artstation.com/

![screenshot](https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/showcase/showcase1.png)
