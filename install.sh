#!/bin/bash

set -e
exec > >(tee -a "install.log") 2>&1

## PACKAGE LISTS

PACKAGES="
    act
    aircrack-ng
    alsa-firmware
    amdgpu_top
    ani-cli-git
    app2unit
    argon2
    aseprite
    audacity
    awakened-poe-trade-git
    bat
    bc
    bemenu-wayland
    bettercap-git
    betterdiscord-installer
    bind
    bleachbit
    blender
    blueberry
    bluez
    bluez-utils
    boomer-git
    boscaceoil
    bottles
    brightnessctl
    btop
    bun-bin
    burpsuite
    caligula
    cargo-binstall
    cargo-deny
    cargo-edit
    cargo-expand
    cargo-flamegraph
    cargo-fuzz
    cargo-llvm-cov
    cargo-machete
    cargo-make
    cargo-show-asm
    cargo-shuttle
    cargo-sort-derives
    cargo-tauri
    cargo-update
    cargo-watch
    cava
    cgdb
    chatgpt-desktop-bin
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
    croc
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
    easyeffects
    ecgen-git
    efibootmgr
    elan-lean
    elephant
    elephant-archlinuxpkgs
    elephant-calc
    elephant-clipboard
    elephant-desktopapplications
    elephant-files
    elephant-menus
    elephant-providerlist
    elephant-runner
    elephant-symbols
    elephant-todo
    elephant-unicode
    elephant-websearch
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
    flameshot
    flat-remix-gtk
    flatpak
    font-manager
    ftxui
    fzf
    gamemode
    gamescope
    gcc
    gcc-fortran
    gdb
    gearlever
    genius
    geogebra-6-bin
    gf2-git
    ghcup-hs-bin
    ghidra
    ghostmirror
    ghostty
    giflib
    gimp
    git
    git-delta
    git-filter-repo
    github-cli
    github-copilot-cli
    gitleaks
    glfw
    glm
    glow
    gnome
    gnome-boxes
    gnome-calculator
    gnome-calendar
    gnome-maps
    gnome-text-editor
    gnuplot
    gnutls
    go
    gobuster
    gparted
    graphviz
    grex
    grim
    gst-plugin-pipewire
    gtk3
    gtk4
    gufw
    handbrake
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
    identity
    imagemagick
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
    kpat
    krita
    kubectl
    kvirc
    lact
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
    lmms
    localsend
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
    metadata-cleaner
    metasploit
    micro
    millennium
    minecraft-launcher
    mingw-w64-gcc
    minikube
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
    openbsd-netcat
    opencl-icd-loader
    opencomposite-git
    openscad
    openssh
    openssl
    openvpn
    osmium-tool
    ossec-hids-local
    osslsigncode
    pandoc-cli
    parallel
    pass
    pastel
    path-of-building-community-git
    pavucontrol
    pdftk
    phoronix-test-suite
    picom
    pipeline-gtk
    piper
    pipewire
    pipewire-alsa
    pipewire-pulse
    pitivi
    pkgconf
    planify
    polkit
    polkit-kde-agent
    portmaster-bin
    postgresql
    postgresql-libs
    powerline-fonts
    pre-commit
    prettier
    protonup-git
    python-black
    python-faker
    python-isort
    python-matplotlib
    python-numpy
    python-pandas
    python-pillow
    python-pip
    python-poetry
    python-pywalfox
    python-scikit-learn
    python-scipy
    python-sympy
    python-validity-git
    pywal-spicetify
    qbe
    qbittorrent
    qemu-full
    qmk
    qpwgraph
    qt5
    qt5-wayland
    qt6
    qt6-wayland
    quickjs
    qutebrowser
    r
    r2modman-bin
    rainfrog
    ranger
    rar
    rawtherapee
    raylib
    reaver-wps-fork-t6x-git
    ripgrep
    rkhunter
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
    snapshot
    sof-firmware
    sox
    spicetify-cli
    spotify
    sqlite
    sqlitebrowser
    sqlmap-git
    sqlx-cli
    sshfs
    starship
    steam
    stirling-pdf-bin
    switcheroo
    swww
    system-config-printer
    tar
    taskwarrior-tui
    teamspeak3
    telegram-desktop
    terminus-font-ttf
    terraform
    texlive
    texlive-lang
    texmaker
    themix-gui-git
    themix-plugin-base16-git
    thunderbird
    tig
    tiled
    timeshift
    timew
    tk
    tldr
    tlp
    tlpui
    tmux
    tokei
    torbrowser-launcher
    tparted-bin
    trash-cli
    trufflehog
    ttf-anonymous-pro
    ttf-arphic-ukai
    ttf-arphic-uming
    ttf-atkinson-hyperlegible
    ttf-baekmuk
    ttf-caladea
    ttf-cascadia-code
    ttf-charis
    ttf-charis-sil
    ttf-cormorant
    ttf-crimson
    ttf-crimson-pro
    ttf-crimson-pro-variable
    ttf-croscore
    ttf-doulos-sil
    ttf-droid
    ttf-eurof
    ttf-fantasque-sans-mono
    ttf-fira-code
    ttf-fira-mono
    ttf-fira-sans
    ttf-gentium
    ttf-gentium-book
    ttf-gentium-plus
    ttf-hack
    ttf-hanazono
    ttf-hannom
    ttf-ibm-plex
    ttf-inconsolata
    ttf-indic-otf
    ttf-input
    ttf-input-nerd
    ttf-jetbrains-mono
    ttf-jigmo
    ttf-junicode
    ttf-junicode-variable
    ttf-khmer
    ttf-lato
    ttf-libertinus
    ttf-linux-libertine
    ttf-linux-libertine-g
    ttf-material-icons
    ttf-material-symbols-variable
    ttf-mona-sans
    ttf-monaspace-frozen
    ttf-monaspace-variable
    ttf-monofur
    ttf-monoid
    ttf-montserrat
    ttf-ms-fonts
    ttf-nunito
    ttf-opensans
    ttf-overpass
    ttf-roboto
    ttf-roboto-mono
    ttf-sarasa-gothic
    ttf-sazanami
    ttf-scheherazade-new
    ttf-tibetan-machine
    ttf-ubuntu-font-family
    ttf-vlgothic
    unzip
    update-grub
    upscaler
    v4l-utils
    valgrind
    ventoy-bin
    veracrypt
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
    wayvr-dashboard
    wget
    whatsdesk-bin
    whois
    wiki-tui
    winboat-bin
    wine-staging
    wireguard-tools
    wireguard-ui-bin
    wireless_tools
    wiremix
    wireplumber
    wireshark-qt
    wivrn-dashboard
    wivrn-server
    wl-clipboard
    wl_shimeji-git
    wlogout
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
    ydotool
    zig
    zip
    zoxide
    zsh
"

CARGO_PKGS="
    bacon
    bootimage
    cargo-info
    cross
    irust
    mprocs
    rustfilt
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

# force rustup and stable, since a lot of packages would otherwise install rust and conflict
sudo pacman -S rustup --noconfirm
rustup default stable

yay -S $PACKAGES --noconfirm
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm

# downgrade cmake to latest 3.* since not enough support for 4.* yet...
sudo pacman -U --noconfirm https://archive.archlinux.org/packages/c/cmake/cmake-3.31.6-1-x86_64.pkg.tar.zst

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

./scripts/switch-wallpaper.sh ~/code/arch-dotfiles/wallpapers/fantasy-landscape2.png >/dev/null 2>/dev/null

sleep 15
sleep 120 && reboot &

echo "Done. Please reboot." | nvim
