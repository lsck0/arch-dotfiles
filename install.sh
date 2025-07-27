#!/bin/bash

set -e

## PACKAGE LISTS

PACKAGES="
    act
    aircrack-ng
    alacritty
    amdgpu_top
    amf-amdgpu-pro
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
    boomer-git
    bottles
    brightnessctl
    btop
    bun-bin
    burpsuite
    caligula
    candy-icons-git
    cgdb
    chromium
    clang
    cloc
    cmake
    cmatrix
    codelldb-bin
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
    dolphin
    downgrade
    dua-cli
    durdraw
    dust
    dysk
    efibootmgr
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
    kdenlive
    kitty
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
    luarocks
    lutris
    ly
    make
    mako
    man-db
    man-pages
    mangohud
    mdbook
    meson
    metasploit
    minecraft-launcher
    mingw-w64-gcc
    minikube
    mirro-rs
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
    onefetch
    onlyoffice-bin
    opam
    openal
    opencl-icd-loader
    openssh
    openssl
    openvpn
    osmium-tool
    pandoc-cli
    parallel
    pass
    pastel
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
    qbe
    qbittorrent
    qemu-full
    qmk
    qt5-wayland
    qt6-wayland
    quickjs
    quickshell
    qutebrowser
    r
    r2modman-bin
    rainfrog
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
    system-config-printer
    tar
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
    webcamize
    wezterm
    wget
    whatsdesk-bin
    wiki-tui
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
    xh
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
    rtx-cli
    rustfilt
    tauri-cli
    tmux-sessionizer
"

# some things have missing dependencies or interfere with other things, so do later
# elan: needs rust and would default to rust and not rustup
# pywal-spicetify: -||-
LATER_PACKAGES="
    elan-lean
    pywal-spicetify
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

# fix zlib conflict
#echo "!!! you might need to overwrite zlib here, please do so !!!"
#sudo pacman -S zlib-ng-compat

sudo pacman -S --needed --noconfirm git base-devel && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay/ && \
    sudo rm -rf ${HOME}/go/

yay -S $PACKAGES --noconfirm
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm

# downgrade cmake to latest 3.* since not enough support for 4.* yet...
sudo pacman -U --noconfirm https://archive.archlinux.org/packages/c/cmake/cmake-3.31.6-1-x86_64.pkg.tar.zst

rustup default nightly
cargo install $CARGO_PKGS -j $(nproc)

yay -S $LATER_PACKAGES --noconfirm

# manual installs
git clone https://github.com/lsck0/wayland-boomer.git ~/.cache/wayland-boomer && cd ~/.cache/wayland-boomer && make install && cd -
git clone https://github.com/SnarkyDeveloper/pywal-discord.git ~/.cache/pywal-discord && cd ~/.cache/pywal-discord && sudo ./install && cd -

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -rf aws/

rm -rf ~/.config/emacs
git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.config/emacs
~/.config/emacs/bin/doom install --aot --force

# other package managers
sudo nix-channel --add https://nixos.org/channels/nixpkgs-unstable
sudo nix-channel --update

/bin/hyprpm update
yes | /bin/hyprpm add https://github.com/hyprwm/hyprland-plugins --force
yes | /bin/hyprpm add https://github.com/VirtCode/hypr-dynamic-cursors --force
/bin/hyprpm enable dynamic-cursors

opam init --no-setup

/usr/bin/ghcup install ghc
/usr/bin/ghcup install cabal
/usr/bin/ghcup install hls
/usr/bin/ghcup install stack

/usr/bin/elan default nightly

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

sudo systemctl enable cronie.service
sudo systemctl enable cups
sudo systemctl enable docker.service
sudo systemctl enable firewalld.service
sudo systemctl enable ly.service
sudo systemctl enable nix-daemon
sudo systemctl enable sshd

git config --global credential.helper store

~/.cargo/bin/tms config -p ${HOME}/code

sudo chmod 777 /opt/spotify
sudo chmod 777 /opt/spotify/Apps -R

./scripts/switch-wallpaper.sh Random

sleep 10 && reboot
