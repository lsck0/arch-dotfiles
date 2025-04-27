<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

Arch Linux Hyprland/i3 installation and configuration files.

Run

```bash
git clone https://github.com/lsck0/arch-dotfiles.git ~/code/arch-dotfiles/
cd ~/code/arch-dotfiles/
./install.sh
```

in after archinstall minimal with btrfs to setup the system.
Note: Some configs rely on being in the folder specified above.

## Things to do manually after

- fetch the submodules (needs github auth)

```bash
git submodule update --init --recursive
```

- import shh and pgp keys from secrets submodule

```bash
gpg --import ~/code/arch-dotfiles/configs/secrets/pgp_privatekey.asc
ssh-add ~/code/arch-dotfiles/configs/secrets/ssh_privatekey.asc
```

- login to discord and spotify and install spicetify and better discord

```bash
spicetify config current_theme Sleek
spicetify config color_scheme UltraBlack
spicetify backup apply
betterdiscord-installer
```

## Todo

- [ ] add aws v2 cli back (aur package atm broken)
