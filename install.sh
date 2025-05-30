#!/bin/bash

set -e

## PACKAGE LISTS

PACKAGES="
    act
    aircrack-ng
    alacritty
    ani-cli-git
    argon2
    aseprite
    audacity
    auto-cpufreq
    baobab
    bemenu-wayland
    bettercap-git
    betterdiscord-installer
    bleachbit
    blender
    boomer-git
    bottles
    brave-bin
    brightnessctl
    btop
    bun-bin
    burpsuite
    candy-icons-git
    cgdb
    chromium
    clang
    cloc
    cmake
    cmatrix
    code
    codelldb-bin
    copyq
    coreutils
    cosmic
    cowsay
    cronie
    cups
    curl
    curseforge
    diesel-cli
    discord
    dmenu
    docker
    docker-buildx
    docker-compose
    dolphin
    downgrade
    efibootmgr
    elan-lean
    emacs
    emscripten
    entr
    fasm
    fastfetch
    fcrackzip
    fd
    feh
    ffmpeg
    file
    filelight
    filezilla
    firefox
    flameshot
    flat-remix-gtk
    flatpak
    flatpak-docs
    flatpak-xdg-utils
    font-manager
    fzf
    gamemode
    gamescope
    gcc
    gdb
    gedit
    genius
    gf2-git
    ghcup-hs-bin
    ghidra-git-bin
    ghostmirror
    ghostty
    giflib
    gimp
    git
    git-filter-repo
    github-cli
    glfw
    glm
    glow
    gnome-boxes
    gnuplot
    gnutls
    go
    gobuster
    gparted
    graphviz
    grim
    gtk3
    gtk4
    gufw
    handlr-regex
    hashcat
    headsetcontrol
    hollywood
    htop
    hydra
    hyperfine
    hyprcursor
    hypridle
    hyprland
    hyprlock
    hyprpaper
    hyprpicker
    hyprsunset
    i3-wm
    i3blocks
    i3lock
    i3status
    imagemagick
    inkscape
    ipython
    iwd
    john
    jq
    jupyterlab
    kate
    kdenlive
    kitty
    krita
    kubectl
    kvirc
    lapce
    lazydocker-bin
    lazygit
    lcov
    lf
    lib32-alsa-lib
    lib32-alsa-plugins
    lib32-giflib
    lib32-gnutls
    lib32-gst-plugins-base-libs
    lib32-gtk3
    lib32-libgcrypt
    lib32-libgpg-error
    lib32-libjpeg-turbo
    lib32-libldap
    lib32-libpng
    lib32-libpulse
    lib32-libva
    lib32-libxcomposite
    lib32-libxinerama
    lib32-libxslt
    lib32-mesa
    lib32-mpg123
    lib32-ncurses
    lib32-openal
    lib32-opencl-icd-loader
    lib32-sqlite
    lib32-v4l-utils
    lib32-vulkan-icd-loader
    lib32-vulkan-icd-loader
    lib32-vulkan-radeon
    libgcrypt
    libgpg-error
    libjpeg-turbo
    libldap
    libnotify
    libpng
    libpqxx
    libpulse
    libreoffice-fresh
    libva
    libx11
    libxcomposite
    libxinerama
    libxslt
    linux-tools-meta
    llvm
    logseq-desktop-bin
    lolcat
    lua51-luautf8
    lutris
    ly
    make
    mako
    man-db
    man-pages
    mangohud
    meson
    metasploit
    minecraft-launcher
    mingw-w64-gcc
    minikube
    mirro-rs
    modrinth-app
    mold
    mpg123
    mpv
    nano
    nasm
    ncurses
    nemo
    neochat
    neofetch
    neovim
    neovim-qt
    networkmanager
    nftables
    ninja
    nix
    nmap
    nodejs
    noto-fonts
    noto-fonts-emoji
    noto-fonts-extra
    npm
    nsxiv
    ntfs-3g
    nushell
    nwg-look
    obs-studio
    obsidian
    odin
    oh-my-zsh-git
    okular
    onefetch
    onlyoffice-bin
    opam
    openal
    opencl-icd-loader
    openssh
    openssl
    osmium-tool
    pandoc-cli
    parallel
    pass
    path-of-building-community-git
    pavucontrol
    pdftk
    picom
    pipewire
    pitivi
    pkgconf
    plasma
    polkit
    polkit-kde-agent
    postgresql
    postgresql-libs
    powerline-fonts
    pre-commit
    protonup-git
    python-black
    python-isort
    python-matplotlib
    python-numpy
    python-pandas
    python-pillow
    python-pip
    python-poetry
    python-scapy
    python-scikit-learn
    python-sympy
    python-validity-git
    qbe
    qemu-full
    qmk
    qt5-wayland
    qt6-wayland
    qutebrowser
    r
    r2modman-bin
    ranger
    raylib
    reaver-wps-fork-t6x-git
    ripgrep
    rstudio-desktop-bin
    rsync
    rustup
    rz-cutter
    sane
    sdl3
    sfxr-qt-bin
    slurp
    smartmontools
    sox
    spicetify-cli
    spotify
    sqlite
    sqlitebrowser
    sqlmap-git
    sqlx-cli
    steam
    system-config-printer
    tar
    terminus-font-ttf
    terraform
    texlive
    texlive-lang
    thunderbird
    tilix
    tk
    tldr
    tlp
    tmux
    tokei
    torbrowser-launcher
    tparted-bin
    trash-cli
    ttf-caladea
    ttf-fira-code
    ttf-hanazono
    ttf-ms-fonts
    ttf-opensans
    typst
    unzip
    update-grub
    v4l-utils
    valgrind
    ventoy-bin
    vim
    virt-manager
    volatility3-git
    vulkan-icd-loader
    vulkan-radeon
    waybar
    wayland
    wezterm
    wget
    whatsdesk-bin
    wine-staging
    wireless_tools
    wireplumber
    wireshark-qt
    wl-clipboard
    wlogout
    wofi
    wpa_supplicant
    wpscan-git
    xclip
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-ninja
    xdg-user-dirs
    xdg-user-dirs-gtk
    xdg-utils
    xed
    xf86-input-synaptics
    xorg-server
    xorg-xauth
    xorg-xeyes
    xorg-xhost
    xorg-xinput
    xorg-xwayland
    xournalpp
    xterm
    xwaylandvideobridge
    ydotool
    zed
    zig
    zip
    zsh
"

CARGO_PKGS="
    bacon
    bat
    bootimage
    cargo-binstall
    cargo-deny
    cargo-edit
    cargo-expand
    cargo-info
    cargo-llvm-cov
    cargo-machete
    cargo-make
    cargo-show-asm
    cargo-shuttle
    cargo-update
    cargo-watch
    cross
    du-dust
    eza
    flamegraph
    fuzz
    irust
    mdbook
    netscanner
    rainfrog
    rtx-cli
    serie
    starship
    tmux-sessionizer
    zoxide
"

## REMOVE PASSWORD FROM SUDO

if ! sudo grep -q '$USER' /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
fi

## LINK PACMAN CONFIG

pushd ./configs/pacman
sh ./link.sh
popd

# INSTALLING ALL THE THINGS

sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Syyu --noconfirm

# fix zlib conflict
echo "!!! you might need to overwrite zlib here, please do so !!!"
sudo pacman -S zlib-ng-compat

sudo pacman -S --needed --noconfirm git base-devel && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay/ && \
    sudo rm -rf ${HOME}/go/

yay -S $PACKAGES --noconfirm
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm

## downgrade cmake to latest 3.* since not enough support for 4.* yet...
sudo pacman -U --noconfirm https://archive.archlinux.org/packages/c/cmake/cmake-3.31.6-1-x86_64.pkg.tar.zst

sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable
sudo nix-channel --update

rustup default nightly
cargo install $CARGO_PKGS -j 16

sudo chown root ~/.cargo/bin/netscanner
sudo chmod u+s ~/.cargo/bin/netscanner

opam init --no-setup

/usr/bin/ghcup install ghc
/usr/bin/ghcup install cabal
/usr/bin/ghcup install hls
/usr/bin/ghcup install stack

/usr/bin/elan default nightly

rm -rf ~/.config/emacs
git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.config/emacs
~/.config/emacs/bin/doom install --aot --force

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws/

## LINK

echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config"      | sudo tee -a /etc/security/pam_env.conf
echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache"       | sudo tee -a /etc/security/pam_env.conf
echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf

find "$(pwd)" -type f -name 'link.sh' | xargs -I {} sh -c 'cd $(dirname {}) && sh $(basename {})'
find "$(pwd)" -type f -name 'link.py' | xargs -I {} sh -c 'cd $(dirname {}) && python $(basename {})'

## FURTHER CONFIG

sudo update-grub

sudo chsh $USER -s /bin/zsh

sudo gpasswd -a $USER docker

sudo systemctl enable ly.service
sudo systemctl enable cups
sudo systemctl enable sshd
sudo systemctl enable nix-daemon

git config --global credential.helper store

~/.cargo/bin/tms config -p ${HOME}/code

sudo chmod 777 /opt/spotify
sudo chmod 777 /opt/spotify/Apps -R
