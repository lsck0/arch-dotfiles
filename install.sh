#!/usr/bin/env bash

set -e
exec > >(tee -a "install.log") 2>&1

FAILURES_FILE="$(pwd)/FAILURES"
: > "$FAILURES_FILE"

## PACKAGE LISTS

PACKAGES="
    act
    afl++
    age
    aircrack-ng
    alsa-firmware
    amdgpu_top
    android-ndk
    android-sdk
    ani-cli-git
    app2unit
    argon2
    aseprite
    audacity
    awww
    bacon
    bat
    bc
    bemenu-wayland
    bettercap-git
    betterdiscord-installer
    biber
    bind
    bleachbit
    blender
    blueberry
    bluez
    bluez-utils
    brightnessctl
    btop
    bugwarrior
    burpsuite
    caligula
    cargo-audit
    cargo-binstall
    cargo-bloat
    cargo-deny
    cargo-edit
    cargo-expand
    cargo-flamegraph
    cargo-fuzz
    cargo-generate
    cargo-llvm-cov
    cargo-machete
    cargo-make
    cargo-show-asm
    cargo-shuttle
    cargo-sort-derives
    cargo-tarpaulin
    cargo-tauri
    cargo-update
    cargo-watch
    cargo-wizard
    cava
    cgdb
    chromium
    clang
    claude-code
    cloc
    clonezilla
    cmake
    cmatrix
    codelldb-bin
    converseen
    copyq
    coreutils
    cowsay
    cpufetch
    croc
    cronie
    cross
    ctop
    cups
    cups-pk-helper
    curl
    curseforge
    diesel-cli
    discord
    dmenu
    docker
    docker-buildx
    docker-compose
    dog
    downgrade
    dua-cli
    dust
    dwarfs-bin
    dysk
    easyeffects
    ecgen-git
    efibootmgr
    elan-lean
    element
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
    expect
    exploitdb
    eza
    famistudio-bin
    fasm
    fastfetch
    fcrackzip
    fd
    feh
    ffmpeg
    figlet
    file
    filezilla
    firefox
    flameshot
    flat-remix-gtk
    flatpak
    font-manager
    foremost
    ftxui
    fzf
    gamemode
    gamescope
    gcc
    gcc-fortran
    gdb
    gearlever
    gemini-cli-git
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
    git-lfs
    github-cli
    github-copilot-cli
    gitleaks
    glava
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
    gtk3
    gtk4
    gufw
    handbrake
    hashcat
    headsetcontrol
    helm
    help2man
    heroic-games-launcher-bin
    hexchat
    hotspot
    hydra
    hyperfine
    hyprcursor
    hypridle
    hyprland
    hyprlock
    hyprpicker
    hyprsunset
    identity
    imagemagick
    inkscape
    intel-media-driver
    ipython
    iwd
    jdownloader2
    jetbrains-toolbox
    jless
    john
    jq
    jujutsu
    jupyterlab
    just
    kdenlive
    kitty
    kpat
    krita
    kubectl
    kvirc
    lazydocker-bin
    lazygit
    lazyjj
    lcov
    lib32-alsa-lib
    lib32-alsa-plugins
    lib32-giflib
    lib32-gnutls
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
    libev
    libgcrypt
    libgpg-error
    libinput-tools
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
    linux-headers
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
    maven
    mdbook
    mesa
    meson
    metadata-cleaner
    metasploit
    micro
    minder
    minecraft-launcher
    mingw-w64-gcc
    minikube
    mise
    mission-center
    modrinth-app-bin
    mold
    mov-cli
    mpg123
    mpv
    mtools
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
    obs-audio-wave-bin
    obs-pipewire-audio-capture
    obs-plugin-waveform-bin
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
    opencode
    opencomposite-git
    openscad
    openssh
    openssl
    opentabletdriver-git
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
    python-numba
    python-numpy
    python-pandas
    python-pillow
    python-pip
    python-poetry
    python-pydantic
    python-pytorch-rocm
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
    rcon-cli
    reaver-wps-fork-t6x-git
    renderdoc
    ripgrep
    rkhunter
    rose-pine-cursor
    rose-pine-hyprcursor
    rstudio-desktop-bin
    rsync
    rz-cutter
    sane
    sccache
    sdl3
    sfxr-qt-bin
    signal-desktop
    skaffold
    skipfish
    slurp
    smartmontools
    snapshot
    socat
    sof-firmware
    sops
    sowon-git
    sox
    speedscope
    spicetify-cli
    spotify
    sqlite
    sqlitebrowser
    sqlmap-git
    sqlx-cli
    sshfs
    sshpass
    starship
    steam
    stirling-pdf-bin
    system-config-printer
    tar
    taskwarrior-tui
    teamspeak3
    telegram-desktop
    terminus-font-ttf
    terraform
    tesseract
    tesseract-data-deu
    tesseract-data-eng
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
    topology-toolkit
    torbrowser-launcher
    tparted-bin
    trash-cli
    tree-sitter-cli
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
    ttf-monocraft-git
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
    tty-clock
    unzip
    update-grub
    uv
    v4l-utils
    v4l2loopback-dkms
    v4l2loopback-utils
    valgrind
    ventoy-bin
    veracrypt
    vim
    virt-manager
    volatility3-git
    vscodium-bin
    vulkan-icd-loader
    vulkan-intel
    vulkan-nouveau
    vulkan-radeon
    walker-bin
    waybar
    waydroid
    wayland
    wayland-boomer-git
    waypipe
    wayvr-bin
    wev
    wget
    whois
    wiki-tui
    wine-staging
    wireguard-tools
    wireguard-ui-bin
    wireless_tools
    wiremix
    wireplumber
    wireshark-qt
    wl-clipboard
    wl_shimeji-git
    wlogout
    wpa_supplicant
    wrk
    wscat
    xclip
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-ninja
    xdg-user-dirs
    xdg-user-dirs-gtk
    xdg-utils
    xf86-input-synaptics
    xf86-video-amdgpu
    xf86-video-ati
    xf86-video-nouveau
    xh
    xivlauncher-bin
    xorg-server
    xorg-xauth
    xorg-xev
    xorg-xeyes
    xorg-xhost
    xorg-xinput
    xorg-xwayland
    xournalpp
    ydotool
    z3
    zaproxy
    zapzap
    zed
    zig
    zip
    zoxide
    zsh
"

CARGO_PKGS="
    bootimage
    cargo-afl
    cargo-info
    cargo-leptos
    cargo-xbuild
    irust
    kani-verifier
    leptosfmt
    rustfilt
    tauri-cli
    tmux-sessionizer
    trunk
"

FLATPAK_PKGS="
    com.jeffser.Alpaca
    de.z_ray.Facetracker
"

## REMOVE PASSWORD FROM SUDO

if ! sudo grep -q '$USER' /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
fi

## LINK PACMAN CONFIG

pushd ./configs/pacman
( set -o pipefail; sh ./link.sh 2>&1 | tee ./link.sh.log ) || echo "configs/pacman/link.sh" >> "$FAILURES_FILE"
popd

## INSTALLING ALL THE THINGS

# update
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Syyu --noconfirm

# install yay
sudo pacman -S --needed --noconfirm git base-devel && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay/

# force rustup and stable, since a lot of packages would otherwise install rust and conflict
sudo pacman -S rustup --noconfirm
rustup default stable

# install all the things
yay -S $PACKAGES --noconfirm --mflags --skipinteg
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm
cargo install $CARGO_PKGS -j $(nproc)
flatpak install flathub -y $FLATPAK_PKGS

# cleanup
rm -rf ${HOME}/.cache/yay/
sudo rm -rf ${HOME}/go/

## LINK

echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config"      | sudo tee -a /etc/security/pam_env.conf
echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache"       | sudo tee -a /etc/security/pam_env.conf
echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf

find "$(pwd)" -type f -name 'link.sh' | while IFS= read -r script; do
    dir=$(dirname "$script"); base=$(basename "$script")
    ( set -o pipefail; cd "$dir" && sh "$base" 2>&1 | tee "${script}.log" ) || echo "$script" >> "$FAILURES_FILE"
done
find "$(pwd)" -type f -name 'link.py' | while IFS= read -r script; do
    dir=$(dirname "$script"); base=$(basename "$script")
    ( set -o pipefail; cd "$dir" && python "$base" 2>&1 | tee "${script}.log" ) || echo "$script" >> "$FAILURES_FILE"
done

## LFS PULL

git lfs pull

## INIT WALLPAPER AND THEME FILES

./scripts/switch-wallpaper.sh ~/code/arch-dotfiles/wallpapers/alena-aenami-revenant2-2-1.jpg >/dev/null 2>/dev/null

## SUMMARY

if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED SCRIPTS ==="
    cat "$FAILURES_FILE"
else
    echo "All scripts succeeded."
    rm -f "$FAILURES_FILE"
fi

## REBOOT

sleep 150 && reboot &

nvim
