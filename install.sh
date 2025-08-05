#!/bin/bash

set -e

## PACKAGE LISTS

PACKAGES="
    act
    aircrack-ng
    alpaca-ai
    amdgpu_top
    ani-cli-git
    argon2
    aseprite
    audacity
    auto-cpufreq
    awakened-poe-trade-git
    bat
    bemenu-wayland
    bettercap-git
    betterdiscord-installer
    blender
    blueberry
    boomer-git
    bottles
    brightnessctl
    btop
    bun-bin
    burpsuite
    caligula
    candy-icons-git
    cava
    cgdb
    chromium
    clang
    cloc
    cmake
    cmatrix
    codechecker
    codelldb-bin
    converseen
    copyq
    coreutils
    cowsay
    cpufetch
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
    downgrade
    dua-cli
    durdraw
    dust
    dysk
    efibootmgr
    elan-lean
    emacs
    emscripten
    entr
    eza
    fasm
    fastfetch
    fcrackzip
    fd
    feh
    ffmpeg
    file
    filezilla
    firefox
    firewalld
    flameshot
    flat-remix-gtk
    font-manager
    fzf
    gamemode
    gamescope
    gcc
    gdb
    gearlever
    genius
    gf2-git
    ghcup-hs-bin
    ghidra
    ghostmirror
    ghostty
    giflib
    gimp
    git
    git-filter-repo
    github-cli
    gitleaks
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
    hashcat
    headsetcontrol
    heroic-games-launcher-bin
    htop
    hydra
    hyperfine
    hyprcursor
    hypridle
    hyprland
    hyprlock
    hyprpicker
    i3-wm
    i3blocks
    i3lock
    i3status
    imagemagick
    impala
    inkscape
    intel-media-driver
    ipython
    iwd
    jdownloader2
    john
    jq
    jupyterlab
    kdenlive
    kitty
    klevernotes
    krita
    kubectl
    kvirc
    lazydocker-bin
    lazygit
    lcov
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
    libva-intel-driver
    libva-mesa-driver
    libx11
    libxcomposite
    libxinerama
    libxslt
    linux-tools-meta
    llvm
    logseq-desktop-bin
    lolcat
    lshw
    lua51-luautf8
    luarocks
    lutris
    ly
    lynis
    lynx
    make
    mako
    man-db
    man-pages
    mangohud
    mdbook
    mesa
    mesa-vdpau
    meson
    metasploit
    millennium
    minecraft-launcher
    mingw-w64-gcc
    minikube
    mirro-rs
    mise
    mission-center
    modrinth-app-bin
    mold
    mpg123
    mpv
    nano
    nasm
    ncdu
    ncurses
    nemo
    neochat
    neofetch
    neovim
    neovim-qt
    netscanner
    networkmanager
    nftables
    nikto
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
    odin
    oh-my-zsh-git
    okular
    ollama-for-amd-git
    onefetch
    onlyoffice-bin
    opam
    openal
    opencl-icd-loader
    openscad
    openssh
    openssl
    openvpn
    osmium-tool
    ossec-hids-local
    pandoc-cli
    parabolic
    parallel
    pass
    pastel
    path-of-building-community-git
    pavucontrol
    pdftk
    picom
    pipeline-gtk
    pipewire
    pitivi
    pkgconf
    planify
    plasma
    polkit
    polkit-kde-agent
    postgresql
    postgresql-libs
    powerline-fonts
    pre-commit
    prettier
    protonup-git
    python-black
    python-isort
    python-numpy
    python-pandas
    python-pillow
    python-pip
    python-poetry
    python-pywalfox
    python-validity-git
    pywal-spicetify
    qbe
    qbittorrent
    qemu-full
    qmk
    qt5-wayland
    qt6-wayland
    quickjs
    qutebrowser
    r
    r2modman-bin
    rainfrog
    ranger
    rawtherapee
    raylib
    reaver-wps-fork-t6x-git
    ripgrep
    rkhunter
    rofi
    rose-pine-cursor
    rose-pine-hyprcursor
    rstudio-desktop-bin
    rsync
    rz-cutter
    sane
    sdl3
    serie
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
    starship
    steam
    switcheroo
    swww
    system-config-printer
    tar
    teamspeak3
    terminus-font-ttf
    terraform
    texlive
    texlive-lang
    themix-gui-git
    themix-plugin-base16-git
    timeshift
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
    upscaler
    v4l-utils
    valgrind
    ventoy-bin
    vim
    virt-manager
    volatility3-git
    vulkan-icd-loader
    vulkan-intel
    vulkan-nouveau
    vulkan-radeon
    walker-bin
    waybar
    waydroid
    wayland
    wayland-boomer-git
    webcamize
    wget
    whatsdesk-bin
    whois
    wiki-tui
    wine-staging
    wireless_tools
    wiremix
    wireplumber
    wireshark-qt
    wl-clipboard
    wl_shimeji-git
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
    xf86-video-amdgpu
    xf86-video-ati
    xf86-video-nouveau
    xh
    xorg-server
    xorg-xauth
    xorg-xeyes
    xorg-xhost
    xorg-xinput
    xorg-xwayland
    xournalpp
    xwaylandvideobridge
    ydotool
    zed
    zig
    zip
    zoxide
    zsh
"

CARGO_PKGS="
    bacon
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
    flamegraph
    fuzz
    irust
    mprocs
    rustfilt
    tauri-cli
    tmux-sessionizer
"

## REMOVE PASSWORD FROM SUDO

if ! sudo grep -q '$USER' /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
fi

## LINK PACMAN CONFIG

pushd ./configs/pacman
sh ./link.sh
popd

## INSTALLING ALL THE THINGS

sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Syyu --noconfirm

sudo pacman -S --needed --noconfirm git base-devel && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay/

# force rustup and nightly, since a lot of packages would otherwise install rust and conflict
sudo pacman -S rustup --noconfirm
rustup default nightly

yay -S $PACKAGES --noconfirm
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm

cargo install $CARGO_PKGS -j $(nproc)

sudo rm -rf ${HOME}/go/

## LINK

echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config"      | sudo tee -a /etc/security/pam_env.conf
echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache"       | sudo tee -a /etc/security/pam_env.conf
echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf

find "$(pwd)" -type f -name 'link.sh' | xargs -I {} sh -c 'cd $(dirname {}) && sh $(basename {})'
find "$(pwd)" -type f -name 'link.py' | xargs -I {} sh -c 'cd $(dirname {}) && python $(basename {})'

## FINALIZE

./scripts/switch-wallpaper.sh random >/dev/null 2>/dev/null

sleep 25

echo "Done. Please reboot."
