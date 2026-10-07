<div align="center">
  <h1>Arch Dotfiles</h1>
</div>

![media, weather and network panels](showcase/showcase1.png)
![media, weather and network panels](showcase/showcase2.png)
![wallpaper picker](showcase/showcase3.png)
![clock, system and app launcher](showcase/showcase4.png)

```bash
curl -fsSL https://install-{pc, notebook, wsl}.lsck0.dev | sh
```

Anyone else, from the Arch ISO (or a fresh WSL Arch root shell):

```bash
curl -fsSL https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh | bash
```

A machine is a `platforms/<name>.sh` or the answers given at install (`/etc/dotfiles/platform.sh`); a user is any
login, with `profiles/<name>.sh` as its profile when there is one, a guest without. Each module has a root
`system.sh`, run once per machine from the root-owned copy `/var/lib/dotfiles/repo`, and a `link.sh` for the user's
home, never with `sudo`. `./install.sh` and `./config.sh` run both for an admin, `--user` only the user's part.

Another login on an installed machine, with its own checkout and user layer:

```bash
adduser-dotfiles <name>
```
