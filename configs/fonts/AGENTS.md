# fonts

Extends the root `AGENTS.md`. The system font set.

## Modules

- `fonts`: the font packages, vendored OFL fonts with no arch package, and the fontconfig defaults as the drop-in
  `~/.config/fontconfig/conf.d/50-dotfiles.conf` (`fonts.conf` itself is the desktop's).

## Conventions

- A font with an arch or AUR package goes in the module's meta packages; only fonts without a package are
  vendored here. Keep the OFL license beside each.
