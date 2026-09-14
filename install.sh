#!/usr/bin/env bash

set -e
exec > >(tee "install.log") 2>&1

FAILURES_FILE="$(pwd)/FAILURES"
: > "$FAILURES_FILE"

# retry N times with exponential backoff. Pacman exit code 8 is "failed to
# commit transaction" — usually a mirror rate-limit or a partially downloaded
# DB, i.e. transient. Retrying the whole command makes a flaky mirror
# survivable instead of aborting the run.
retry() {
    local attempts="$1"; shift
    local n=1 wait_s=5
    until "$@"; do
        if (( n >= attempts )); then
            echo "FAILED after $attempts attempts: $*" >&2
            return 1
        fi
        echo "attempt $n/$attempts failed, retrying in ${wait_s}s: $*" >&2
        sleep "$wait_s"
        n=$(( n + 1 ))
        wait_s=$(( wait_s * 2 ))
    done
}

## PACKAGES
    #   base        - bare Arch security tooling
    #   fonts       - fonts, managers, nerd fonts
    #   desktop     - Hyprland, Plasma, minimal apps
    #   socials     - chat, voice, social apps
    #   gaming      - games and gaming tooling
    #   creating    - Blender, Krita, CAD tools
    #   latex       - LaTeX and BibTeX tooling
    #   programming - editors, agents, toolchains, debuggers
    #   qemu        - QEMU and virtualization tooling
    #   llm         - Ollama, vLLM, ROCm stack
    #   pentesting  - active scanning exploitation tools

# NOTE: the theme-propagation stack lives in base on purpose, so it is always
# installed even when the desktop group is deselected: wallust-git (engine),
# themix-gui-git + themix-plugin-base16-git (themix-multi-export, the GTK
# exporter scripts/switch-wallpaper.sh calls on every wallpaper change),
# python-pywalfox (firefox), imagemagick (magick, used by
# generate-editor-themes.sh), python (generate-*.py scripts) and jq (theme
# scan + generators). themix-gui-git ships a GUI, but its multi-export CLI is
# part of the core theme pipeline, hence the base exception.

PACKAGES=(
    alsa-firmware # [base] ALSA sound firmware
    amdgpu_top # [base] AMD GPU monitor
    app2unit # [base] app to systemd unit
    base # [base] Arch base group
    base-devel # [base] Arch build tools
    bluetui # [base] bluetooth tui
    bluez # [base] bluetooth stack
    bluez-utils # [base] bluetooth utilities
    borg # [base] deduplicating backup tool
    bpftop # [base] bpf monitor
    btop # [base] resource monitor TUI
    btrfs-progs # [base] btrfs filesystem tools
    caligula # [base] disk imaging tool
    chafa # [base] terminal image renderer
    cifs-utils # [base] SMB/CIFS mount tools
    clonezilla # [base] disk cloning tool
    cmatrix # [base] matrix terminal animation
    coreutils # [base] GNU core utilities
    cowsay # [base] ascii cow sayings
    cpufetch # [base] CPU info fetcher
    croc # [base] secure file transfer
    cronie # [base] cron daemon
    cups # [base] printing system
    cups-pdf # [base] print-to-PDF virtual printer
    curl # [base] HTTP client tool
    diskwatch # [base] disk debugging
    dog # [base] DNS lookup tool
    downgrade # [base] pacman package downgrader
    dua-cli # [base] disk usage analyzer
    dwarfs # [base] compressed read-only fs
    dysk # [base] disk usage viewer
    efibootmgr # [base] EFI boot manager
    eza # [base] modern ls replacement
    fail2ban # [base] intrusion prevention tool
    fastfetch # [base] system info fetcher
    fd # [base] find alternative
    ffmpeg # [base] audio/video converter
    file # [base] file type detector
    fzf # [base] fuzzy finder
    flatpak # [base] sandboxed app packages
    ghostmirror # [base] mirrorlist ranking tool
    git # [base] version control
    gnutls # [base] TLS library
    gpg-tui # [base] gpg tui
    gping # [base] ping with graph
    imagemagick # [base] theme generator dependency
    intel-media-driver # [base] Intel VAAPI driver
    ipython # [base] enhanced Python shell
    iwd # [base] iNet wireless daemon
    jolt # [base] battery debugging
    jq # [base] JSON processor CLI
    just # [base] command runner
    kmon # [base] kernel monitor
    lazyjournal # [base] journalctl/log TUI
    less # [base] pager utility
    lib32-alsa-lib # [base] 32-bit ALSA lib
    lib32-alsa-plugins # [base] 32-bit ALSA plugins
    lib32-giflib # [base] 32-bit GIF lib
    lib32-gnutls # [base] 32-bit TLS lib
    lib32-libgcrypt # [base] 32-bit crypto lib
    lib32-libgpg-error # [base] 32-bit gpg errors
    lib32-libjpeg-turbo # [base] 32-bit JPEG lib
    lib32-libldap # [base] 32-bit LDAP lib
    lib32-libpng # [base] 32-bit PNG lib
    lib32-libpulse # [base] 32-bit PulseAudio
    lib32-libva # [base] 32-bit VAAPI lib
    lib32-libxcomposite # [base] 32-bit X composite
    lib32-libxinerama # [base] 32-bit Xinerama lib
    lib32-mesa # [base] 32-bit Mesa drivers
    lib32-mpg123 # [base] 32-bit MP3 decoder
    lib32-ncurses # [base] 32-bit ncurses lib
    lib32-opencl-icd-loader # [base] 32-bit OpenCL loader
    lib32-sqlite # [base] 32-bit SQLite lib
    lib32-vulkan-icd-loader # [base] 32-bit Vulkan loader
    lib32-vulkan-radeon # [base] 32-bit AMD Vulkan
    libappimage # [base] AppImage runtime lib
    libev # [base] event loop library
    libgcrypt # [base] crypto library
    libgpg-error # [base] gpg error codes
    libinput-tools # [base] libinput debug tools
    libjpeg-turbo # [base] JPEG codec library
    libldap # [base] LDAP client library
    libpng # [base] PNG image library
    libpqxx # [base] C++ postgres client
    libpulse # [base] PulseAudio client lib
    libreoffice-fresh # [base] office suite
    libva # [base] VAAPI video accel
    libva-intel-driver # [base] Intel VAAPI driver
    libva-mesa-driver # [base] Mesa VAAPI driver
    libvips # [base] image processing library
    libxcomposite # [base] X composite extension
    libxinerama # [base] X multi-monitor lib
    limine # [base] boot loader
    linux # [base] Linux kernel
    linux-docs # [base] kernel documentation
    linux-firmware # [base] kernel firmware blobs
    linux-hardened # [base] hardened kernel
    linux-hardened-docs # [base] hardened kernel docs
    linux-hardened-headers # [base] hardened kernel headers
    linux-headers # [base] kernel headers
    linux-lts # [base] long-term-support kernel
    linux-lts-docs # [base] LTS kernel docs
    linux-lts-headers # [base] LTS kernel headers
    linux-tools-meta # [base] kernel perf tools
    lolcat # [base] rainbow text output
    lshw # [base] hardware lister
    lua51-luautf8 # [base] Lua UTF-8 lib
    man-pages # [base] Linux manual pages
    mesa # [base] graphics driver library
    metadata-cleaner # [base] strip file metadata
    mtools # [base] DOS filesystem tools
    mtr # [base] traceroute + ping
    ncurses # [base] terminal UI library
    neofetch # [base] system info display
    networkmanager # [base] network connection manager
    nss-mdns # [base] mDNS name resolution
    ntfs-3g # [base] NTFS filesystem driver
    oh-my-zsh-git # [base] zsh config framework
    openal # [base] 3D audio library
    openbsd-netcat # [base] netcat networking tool
    opencl-icd-loader # [base] OpenCL loader
    openssh # [base] SSH client/server
    openssl # [base] TLS/crypto toolkit
    ossec-hids-local # [base] host intrusion detection
    ouch # [base] archive compression tool
    pacman-contrib # [base] pacman cache cleanup tools
    pandoc-cli # [base] document format converter
    parallel # [base] run commands in parallel
    pass # [base] CLI password manager
    pdftk # [base] PDF toolkit
    pipewire # [base] audio/video server
    pipewire-alsa # [base] pipewire ALSA compat
    pipewire-pulse # [base] pipewire pulse compat
    plasma-integration # [base] Qt platform theme
    plymouth # [base] boot splash screen
    portmaster-bin # [base] application firewall
    procs # [base] modern ps replacement
    python # [base] theme generator scripts
    python-pywalfox # [base] firefox theme propagator
    python-validity-git # [base] fingerprint reader driver
    ranger # [base] terminal file manager
    rar # [base] RAR archive tool
    rclone # [base] cloud storage sync
    rsync # [base] file sync tool
    rustnet # [base] network monitor TUI
    s-tui # [base] CPU stress/monitor TUI
    sane # [base] scanner access library
    sbctl # [base] Secure Boot key management
    sd # [base] sed alternative CLI
    smartmontools # [base] disk health monitoring
    socat # [base] socket relay tool
    sof-firmware # [base] sound open firmware
    sshfs # [base] SSH filesystem mount
    sshpass # [base] non-interactive SSH auth
    starship # [base] cross-shell prompt
    stirling-pdf-bin # [base] PDF manipulation tool
    sudo # [base] privilege escalation tool
    superseedr # [base] terminal torrent
    tar # [base] archiving utility
    tar-scripts # [base] tar helper scripts
    themix-gui-git # [base] GTK theme exporter
    themix-plugin-base16-git # [base] themix export plugin
    thermald # [base] thermal management daemon
    timeshift # [base] system backup/restore
    timeshift-autosnap # [base] pacman hook for pre-upgrade snapshots
    tk # [base] Tcl/Tk GUI toolkit
    tldr # [base] simplified man pages
    tlp # [base] laptop power management
    tmux # [base] terminal multiplexer
    tmux-fingers # [base] tmux copy-paste hints
    tparted-bin # [base] partitioning TUI tool
    traceroute # [base] network route tracer
    trash-cli # [base] CLI trash bin
    trippy # [base] traceroute + ping TUI
    tty-clock # [base] terminal clock display
    unzip # [base] zip extraction tool
    usage # [base] CLI docs generator
    usbtree # [base] usb tui
    v4l-utils # [base] video4linux utilities
    v4l2loopback-dkms # [base] virtual video device
    v4l2loopback-utils # [base] v4l2loopback helper tools
    ventoy-bin # [base] multi-boot USB creator
    vim # [base] modal text editor
    vulkan-icd-loader # [base] Vulkan loader library
    vulkan-intel # [base] Intel Vulkan driver
    vulkan-nouveau # [base] Nvidia open Vulkan
    vulkan-radeon # [base] AMD Vulkan driver
    wallust-git # [base] wallpaper colour engine
    wget # [base] file download utility
    whois # [base] domain lookup tool
    wiki-tui # [base] Wikipedia terminal browser
    wireless_tools # [base] legacy wireless config
    wpa_supplicant # [base] wifi authentication daemon
    xdg-ninja # [base] XDG compliance checker
    xdg-user-dirs # [base] standard user directories
    xdg-utils # [base] desktop integration utilities
    xf86-video-ati # [base] legacy AMD driver
    xf86-video-nouveau # [base] open Nvidia driver
    yay # [base] AUR helper
    yazi # [base] terminal file manager
    yt-dlp # [base] video downloader
    zip # [base] zip archiving tool
    zoxide # [base] smarter cd command
    zram-generator # [base] compressed swap generator
    zsh # [base] Z shell

    noto-fonts # [fonts] Google Noto fonts
    noto-fonts-emoji # [fonts] Noto emoji fonts
    noto-fonts-extra # [fonts] Noto extra fonts
    otf-atkinsonhyperlegiblemono-nerd # [fonts] Atkinson Hyperlegible Mono Nerd Font
    otf-aurulent-nerd # [fonts] Aurulent Sans Nerd Font
    otf-codenewroman-nerd # [fonts] Code New Roman Nerd Font
    otf-comicshanns-nerd # [fonts] Comic Shanns Nerd Font
    otf-commit-mono-nerd # [fonts] Commit Mono Nerd Font
    otf-droid-nerd # [fonts] Droid Sans Mono Nerd Font
    otf-firamono-nerd # [fonts] Fira Mono Nerd Font
    otf-geist-mono-nerd # [fonts] Geist Mono Nerd Font
    otf-hasklig-nerd # [fonts] Hasklig Nerd Font
    otf-hermit-nerd # [fonts] Hermit Nerd Font
    otf-monaspace-nerd # [fonts] MonoSpace Nerd Font
    otf-opendyslexic-nerd # [fonts] OpenDyslexic Nerd Font
    otf-overpass-nerd # [fonts] Overpass Nerd Font
    powerline-fonts # [fonts] powerline symbol fonts
    terminus-font-ttf # [fonts] bitmap terminal font
    ttf-0xproto-nerd # [fonts] 0xProto Nerd Font
    ttf-3270-nerd # [fonts] 3270 Nerd Font
    ttf-adwaitamono-nerd # [fonts] Adwaita Mono Nerd Font
    ttf-agave-nerd # [fonts] Agave Nerd Font
    ttf-annotationmono-nerd # [fonts] Annotation Mono Nerd Font
    ttf-anonymous-pro # [fonts] monospace font
    ttf-anonymouspro-nerd # [fonts] Anonymous Pro Nerd Font
    ttf-arimo-nerd # [fonts] Arimo Nerd Font
    ttf-arphic-ukai # [fonts] Chinese kai font
    ttf-arphic-uming # [fonts] Chinese ming font
    ttf-atkinson-hyperlegible # [fonts] accessible reading font
    ttf-baekmuk # [fonts] Korean font family
    ttf-bigblueterminal-nerd # [fonts] Big Blue Terminal Nerd Font
    ttf-bitstream-vera-mono-nerd # [fonts] Bitstream Vera Mono Nerd Font
    ttf-caladea # [fonts] Cambria-metric font
    ttf-cascadia-code # [fonts] monospace coding font
    ttf-cascadia-code-nerd # [fonts] Cascadia Code Nerd Font
    ttf-cascadia-mono-nerd # [fonts] Cascadia Mono Nerd Font
    ttf-cormorant # [fonts] serif display font
    ttf-cousine-nerd # [fonts] Cousine Nerd Font
    ttf-crimson # [fonts] serif text font
    ttf-crimson-pro # [fonts] serif text font
    ttf-crimson-pro-variable # [fonts] variable serif font
    ttf-croscore # [fonts] Chrome OS fonts
    ttf-d2coding-nerd # [fonts] D2Coding Nerd Font
    ttf-daddytime-mono-nerd # [fonts] DaddyTime Mono Nerd Font
    ttf-dejavu-nerd # [fonts] DejaVu Nerd Font
    ttf-doulos-sil # [fonts] phonetic Unicode font
    ttf-droid # [fonts] Android system fonts
    ttf-envycoder-nerd # [fonts] EnvyCoder Nerd Font
    ttf-eurof # [fonts] Eurostile-style font
    ttf-fantasque-nerd # [fonts] Fantasque Sans Mono Nerd Font
    ttf-fantasque-sans-mono # [fonts] quirky monospace font
    ttf-fira-code # [fonts] ligature coding font
    ttf-fira-mono # [fonts] monospace font
    ttf-fira-sans # [fonts] humanist sans font
    ttf-firacode-nerd # [fonts] Fira Code Nerd Font
    ttf-gentium # [fonts] serif Unicode font
    ttf-gentium-book # [fonts] serif book font
    ttf-gentium-plus # [fonts] extended serif font
    ttf-go-nerd # [fonts] Go Nerd Font
    ttf-gohu-nerd # [fonts] Gohu Nerd Font
    ttf-googlesanscode-nerd # [fonts] Google Sans Code Nerd Font
    ttf-hack # [fonts] monospace coding font
    ttf-hack-nerd # [fonts] Hack Nerd Font
    ttf-hanazono # [fonts] Japanese CJK font
    ttf-hannom # [fonts] Vietnamese Han-Nom font
    ttf-heavydata-nerd # [fonts] Heavy Data Nerd Font
    ttf-iawriter-nerd # [fonts] iA Writer Nerd Font
    ttf-ibm-plex # [fonts] IBM typeface family
    ttf-ibmplex-mono-nerd # [fonts] IBM Plex Mono Nerd Font
    ttf-inconsolata # [fonts] monospace coding font
    ttf-inconsolata-go-nerd # [fonts] Inconsolata Go Nerd Font
    ttf-inconsolata-lgc-nerd # [fonts] Inconsolata LGC Nerd Font
    ttf-inconsolata-nerd # [fonts] Inconsolata Nerd Font
    ttf-indic-otf # [fonts] Indic script fonts
    ttf-input # [fonts] coding-focused font
    ttf-input-nerd # [fonts] Input font + icons
    ttf-intone-nerd # [fonts] Intone Nerd Font
    ttf-iosevka-nerd # [fonts] Iosevka Nerd Font
    ttf-iosevkaterm-nerd # [fonts] Iosevka Term Nerd Font
    ttf-iosevkatermslab-nerd # [fonts] Iosevka Term SLAB Nerd Font
    ttf-jetbrains-mono # [fonts] monospace coding font
    ttf-jetbrains-mono-nerd # [fonts] JetBrains Mono Nerd Font
    ttf-jigmo # [fonts] rare CJK glyphs
    ttf-junicode # [fonts] medievalist Unicode font
    ttf-junicode-variable # [fonts] variable medievalist font
    ttf-khmer # [fonts] Khmer script font
    ttf-lato # [fonts] humanist sans font
    ttf-lekton-nerd # [fonts] Lekton Nerd Font
    ttf-liberation-mono-nerd # [fonts] Liberation Mono Nerd Font
    ttf-libertinus # [fonts] classic serif family
    ttf-lilex-nerd # [fonts] Lilex Nerd Font
    ttf-linux-libertine # [fonts] free serif font
    ttf-linux-libertine-g # [fonts] Libertine with graphite
    ttf-martian-mono-nerd # [fonts] Martian Mono Nerd Font
    ttf-material-icons # [fonts] material design icons
    ttf-material-symbols-variable # [fonts] variable material icons
    ttf-meslo-nerd # [fonts] Meslo Nerd Font
    ttf-mona-sans # [fonts] GitHub display font
    ttf-monaspace-frozen # [fonts] GitHub monospace font
    ttf-monaspace-variable # [fonts] variable monospace font
    ttf-monocraft-git # [fonts] Minecraft-style monospace
    ttf-monofur # [fonts] futuristic monospace font
    ttf-monofur-nerd # [fonts] MonoFur Nerd Font
    ttf-monoid # [fonts] coding-focused monospace
    ttf-monoid-nerd # [fonts] Monoid Nerd Font
    ttf-mononoki-nerd # [fonts] Mononoki Nerd Font
    ttf-montserrat # [fonts] geometric sans font
    ttf-mplus-nerd # [fonts] Mplus Nerd Font
    ttf-ms-fonts # [fonts] Microsoft core fonts
    ttf-nerd-fonts-symbols # [fonts] Nerd Fonts Symbols
    ttf-nerd-fonts-symbols-mono # [fonts] Nerd Fonts Symbols Mono
    ttf-noto-nerd # [fonts] Noto Nerd Font
    ttf-nunito # [fonts] rounded sans font
    ttf-opensans # [fonts] humanist sans font
    ttf-overpass # [fonts] highway-gothic sans font
    ttf-profont-nerd # [fonts] ProFont Nerd Font
    ttf-proggyclean-nerd # [fonts] ProggyClean Nerd Font
    ttf-recursive-nerd # [fonts] Recursive Nerd Font
    ttf-roboto # [fonts] Android system font
    ttf-roboto-mono # [fonts] monospace variant font
    ttf-roboto-mono-nerd # [fonts] Roboto Mono Nerd Font
    ttf-sarasa-gothic # [fonts] CJK+Latin coding font
    ttf-sazanami # [fonts] Japanese Gothic font
    ttf-scheherazade-new # [fonts] Arabic script font
    ttf-sharetech-mono-nerd # [fonts] ShareTech Mono Nerd Font
    ttf-sourcecodepro-nerd # [fonts] Source Code Pro Nerd Font
    ttf-space-mono-nerd # [fonts] Space Mono Nerd Font
    ttf-terminus-nerd # [fonts] Terminus Nerd Font
    ttf-tibetan-machine # [fonts] Tibetan script font
    ttf-tinos-nerd # [fonts] Tinos Nerd Font
    ttf-ubuntu-font-family # [fonts] Ubuntu system fonts
    ttf-ubuntu-mono-nerd # [fonts] Ubuntu Mono Nerd Font
    ttf-ubuntu-nerd # [fonts] Ubuntu Nerd Font
    ttf-victor-mono-nerd # [fonts] Victor Mono Nerd Font
    ttf-vlgothic # [fonts] Japanese Gothic font
    ttf-zed-mono-nerd # [fonts] Zed Mono Nerd Font

    ani-cli-git # [desktop] anime streaming CLI
    bemenu-wayland # [desktop] dmenu for wayland
    benben # [desktop] terminal music player
    bleachbit # [desktop] disk space cleaner
    blueberry # [desktop] bluetooth config GUI
    bookokrat # [desktop] terminal pdf
    brightnessctl # [desktop] backlight control
    chromium # [desktop] web browser
    cups-pk-helper # [desktop] cups polkit helper
    filezilla # [desktop] FTP client
    firefox # [desktop] web browser
    flat-remix-gtk # [desktop] GTK theme
    font-manager # [desktop] font management GUI
    gearlever # [desktop] AppImage manager
    ghostty # [desktop] GPU terminal emulator
    gnome-calculator # [desktop] calculator app
    gnome-calendar # [desktop] calendar app
    gnome-maps # [desktop] maps application
    gnome-text-editor # [desktop] simple text editor
    gparted # [desktop] partition editor GUI
    grim # [desktop] wayland screenshot tool
    gtk3 # [desktop] GTK3 toolkit
    gtk4 # [desktop] GTK4 toolkit
    headsetcontrol # [desktop] headset control utility
    hyprcursor # [desktop] hyprland cursor format
    hypridle # [desktop] hyprland idle daemon
    hyprland # [desktop] wayland compositor
    hyprlock # [desktop] wayland screen locker
    hyprpicker # [desktop] wayland color picker
    hyprsunset # [desktop] blue light filter
    jdownloader2 # [desktop] download manager
    kitty # [desktop] GPU terminal emulator
    lib32-gtk3 # [desktop] 32-bit GTK3
    libnotify # [desktop] desktop notification lib
    libx11 # [desktop] X11 client library
    linecast # [desktop] tui weather
    localsend # [desktop] local file sharing
    logseq-desktop-bin # [desktop] note-taking app
    ly # [desktop] TUI display manager
    lynx # [desktop] text-mode web browser
    minder # [desktop] mind mapping tool
    mission-center # [desktop] system monitor GUI
    mov-cli # [desktop] terminal movie streamer
    mpg123 # [desktop] MP3 player CLI
    mpv # [desktop] media player
    nemo # [desktop] file manager
    nwg-look # [desktop] GTK theme configurator
    obsidian # [desktop] markdown notes app
    obsidian-icon-theme # [desktop] Obsidian icon theme
    okular # [desktop] PDF/document viewer
    onlyoffice-bin # [desktop] office document suite
    pavucontrol # [desktop] PulseAudio volume GUI
    piper # [desktop] mouse config GUI
    plasma # [desktop] KDE desktop environment
    playerctl # [desktop] media player control
    polkit # [desktop] privilege authorization framework
    polkit-kde-agent # [desktop] KDE polkit agent
    proton-authenticator-bin # [desktop] Proton 2FA app
    proton-vpn-qt-app # [desktop] ProtonVPN GUI client
    qbittorrent # [desktop] torrent client
    qt5 # [desktop] Qt5 UI toolkit
    qt5-wayland # [desktop] Qt5 wayland platform
    qt6 # [desktop] Qt6 UI toolkit
    qt6-wayland # [desktop] Qt6 wayland platform
    quickshell # [desktop] wayland status bar shell
    qutebrowser # [desktop] keyboard-driven web browser
    rose-pine-cursor # [desktop] cursor theme
    rose-pine-hyprcursor # [desktop] hyprland cursor theme
    slurp # [desktop] wayland region selector
    snapshot # [desktop] GNOME camera app
    sowon-git # [desktop] tsoding timer
    system-config-printer # [desktop] printer config GUI
    tlpui # [desktop] TLP configuration GUI
    torbrowser-launcher # [desktop] Tor Browser launcher
    uwsm # [desktop] universal wayland session manager
    waydroid # [desktop] Android container runtime
    wayland # [desktop] display server protocol
    wayland-boomer-git # [desktop] wayland screen magnifier
    waypipe # [desktop] wayland network forwarding
    wev # [desktop] wayland event viewer
    wine-staging # [desktop] Windows compatibility layer
    wiremix # [desktop] pipewire mixer TUI
    wireplumber # [desktop] pipewire session manager
    wl-clipboard # [desktop] wayland clipboard tool
    wl_shimeji-git # [desktop] desktop mascot pet
    xclip # [desktop] X11 clipboard tool
    xdg-desktop-portal-gtk # [desktop] GTK desktop portal
    xdg-desktop-portal-hyprland # [desktop] hyprland desktop portal
    xdg-user-dirs-gtk # [desktop] user dirs GTK integration
    xf86-input-synaptics # [desktop] touchpad driver
    xf86-video-amdgpu # [desktop] AMD video driver
    xorg-server # [desktop] X11 display server
    xorg-xauth # [desktop] X11 auth utility
    xorg-xev # [desktop] X11 event viewer
    xorg-xeyes # [desktop] X11 demo eyes
    xorg-xhost # [desktop] X11 access control
    xorg-xinput # [desktop] X11 input config
    xorg-xwayland # [desktop] X11 on wayland
    ydotool # [desktop] generic input automation
    zathura # [desktop] minimal document viewer
    zathura-pdf-mupdf # [desktop] zathura PDF backend

    betterdiscord-installer # [socials] BetterDiscord installer
    betterdiscordctl-git # [socials] BetterDiscord CLI installer
    chatuino # [socials] tui twitch
    discord # [socials] chat/voice app
    discordo-git # [socials] terminal discord client
    element # [socials] matrix chat client
    enola # [pentesting] search usernames
    hexchat # [socials] IRC client
    proton-mail-bin # [socials] Proton Mail client
    proton-meet-bin # [socials] Proton video calls
    pywal-spicetify # [socials] pywal spotify theming
    signal-desktop # [socials] encrypted messaging app
    spicetify-cli # [socials] spotify theming CLI
    spotify # [socials] music streaming client
    spotify-player # [socials] terminal spotify client
    teamspeak3 # [socials] voice chat client
    telegram-desktop # [socials] messaging app
    thunderbird # [socials] email client
    zapzap # [socials] WhatsApp desktop client

    curseforge # [gaming] mod manager launcher
    gamemode # [gaming] gaming performance daemon
    gamescope # [gaming] gaming compositor
    heroic-games-launcher-bin # [gaming] epic/gog launcher
    kpat # [gaming] patience card games
    lutris # [gaming] game launcher manager
    mangohud # [gaming] gaming performance overlay
    minecraft-launcher # [gaming] Minecraft game launcher
    modrinth-app # [gaming] minecraft mod manager
    nethack # [gaming] roguelike dungeon game
    path-of-building-community-git # [gaming] PoE build planner
    protontricks # [gaming] Proton/Wine helper tool
    protonup-git # [gaming] Proton-GE installer
    r2modman-bin # [gaming] game mod manager
    rcon-cli # [gaming] game server RCON client
    rogue # [gaming] roguelike dungeon game
    steam # [gaming] gaming platform client
    wayvr-bin # [gaming] wayland VR desktop
    xivlauncher-bin # [gaming] FFXIV game launcher

    aseprite # [creating] pixel art editor
    audacity # [creating] audio editor
    blender # [creating] 3D modeling suite
    cava # [creating] audio visualizer
    converseen # [creating] batch image converter
    drawy # [creating] freehand drawing tool
    easyeffects # [creating] audio effects processor
    famistudio-bin # [creating] NES chiptune tracker
    feh # [creating] lightweight image viewer
    giflib # [creating] GIF image library
    gifsicle # [creating] GIF editing tool
    gimp # [creating] image editing suite
    glava # [creating] audio visualizer
    handbrake # [creating] video transcoder
    identity # [creating] media comparison
    inkscape # [creating] vector graphics editor
    kdenlive # [creating] video editor
    krita # [creating] digital painting app
    lmms # [creating] music production software
    lorien-bin # [creating] infinite canvas drawing
    nsxiv # [creating] lightweight image viewer
    obs-audio-wave-bin # [creating] OBS audio waveform plugin
    obs-pipewire-audio-capture # [creating] OBS pipewire capture
    obs-plugin-waveform-bin # [creating] OBS waveform plugin
    obs-studio # [creating] screen recording/streaming
    obs-studio-plugin-browser # [creating] OBS browser source
    python-websocket-client # [creating] obs-websocket client for the bar's OBS widget
    openscad # [creating] 3D CAD modeler
    opentabletdriver-git # [creating] graphics tablet driver
    pitivi # [creating] video editor
    qpwgraph # [creating] pipewire patchbay GUI
    rawtherapee # [creating] RAW photo editor
    sfxr-qt-bin # [creating] sound effect generator
    sox # [creating] audio processing tool
    tiled # [creating] tilemap editor
    xournalpp # [creating] handwritten note-taking

    biber # [latex] bibliography processor
    bibiman-bin # [latex] tui bibtext manager
    tectonic # [latex] LaTeX engine
    texlab # [latex] LaTeX language server
    texlive # [latex] LaTeX distribution
    texlive-lang # [latex] LaTeX language packs
    texmaker # [latex] LaTeX editor

    act # [programming] run CI locally
    afl++ # [programming] fuzzing tool
    age # [programming] file encryption tool
    avr-binutils # [programming] AVR assembler/linker
    avr-gcc # [programming] AVR C compiler
    avr-gdb # [programming] AVR debugger
    avr-libc # [programming] AVR C library
    android-ndk # [programming] Android native dev kit
    android-sdk # [programming] Android development kit
    appimagetool-git # [programming] build AppImages
    ast-grep # [programming] code structural search
    aws-cli-v2 # [programming] AWS command line
    bacon # [programming] rust background checker
    bat # [programming] cat with highlighting
    bc # [programming] calculator language
    bear # [programming] compile db generator
    bind # [programming] DNS utilities
    bloaty # [programming] binary size profiler
    bugwarrior # [programming] bugtracker to taskwarrior
    cargo-audit # [programming] rust vuln scanner
    cargo-bloat # [programming] rust binary size
    cargo-deny # [programming] rust dependency lint
    cargo-edit # [programming] rust cargo.toml editor
    cargo-expand # [programming] rust macro expansion
    cargo-flamegraph # [programming] rust profiler graphs
    cargo-fuzz # [programming] rust fuzzing tool
    cargo-generate # [programming] rust project templates
    cargo-llvm-cov # [programming] rust coverage tool
    cargo-machete # [programming] unused deps finder
    cargo-make # [programming] rust task runner
    cargo-show-asm # [programming] rust asm viewer
    cargo-shuttle # [programming] shuttle.rs deploy CLI
    cargo-sort-derives # [programming] derive attribute sorter
    cargo-tarpaulin # [programming] rust code coverage
    cargo-tauri # [programming] tauri app CLI
    cargo-update # [programming] update installed crates
    cargo-watch # [programming] rebuild on change
    cargo-wizard # [programming] cargo profile helper
    cargo-zigbuild # [programming] cross-compile via zig
    cdecl # [programming] C declaration translator
    cgdb # [programming] curses gdb frontend
    clang # [programming] C/C++ compiler
    claude-code # [programming] Claude Code CLI
    cloc # [programming] count lines of code
    cmake # [programming] build system generator
    codelldb-bin # [programming] LLDB debugger extension
    cppcheck # [programming] C/C++ static analysis
    crates-tui-git # [programming] crates.rs tui
    cross # [programming] rust cross-compilation
    csvi # [programming] csv editor
    ctop # [programming] container resource monitor
    diesel-cli # [programming] rust ORM CLI
    difftastic # [programming] structural diff tool
    direnv # [programming] per-directory env loader
    dnsglobe # [programming] dns propagation viewer
    docker # [programming] container runtime
    docker-buildx # [programming] docker build extension
    docker-compose # [programming] multi-container orchestration
    ecgen-git # [programming] elliptic curve generator
    elan-lean # [programming] Lean toolchain manager
    emacs # [programming] text editor
    emscripten # [programming] C/C++ to wasm
    entr # [programming] run on file change
    expect # [programming] scripted terminal automation
    fasm # [programming] flat assembler
    figlet # [programming] ascii text banners
    flamelens # [programming] tui flamegraph viewer
    ftxui # [programming] C++ terminal UI lib
    gcc # [programming] C/C++ compiler
    gcc-fortran # [programming] Fortran compiler
    gdb # [programming] GNU debugger
    gemini-cli # [programming] Google Gemini CLI
    genius # [programming] math calculator app
    geogebra-6-bin # [programming] math/geometry app
    gf2-git # [programming] debugger
    gh-dash # [programming] GitHub dashboard TUI
    ghcup-hs-bin # [programming] Haskell toolchain installer
    git-delta # [programming] syntax-highlighting diff pager
    git-filter-repo # [programming] git history rewriter
    git-lfs # [programming] git large file storage
    github-cli # [programming] GitHub CLI (gh)
    github-copilot-cli # [programming] Copilot CLI tool
    glfw # [programming] OpenGL windowing lib
    glm # [programming] OpenGL math library
    glow # [programming] markdown terminal renderer
    gnucobol # [programming] cobol compiler
    gnuplot # [programming] plotting utility
    go # [programming] Go programming language
    godot # [programming] game engine
    gonzo # [programming] tui log analysis
    graphviz # [programming] graph visualization tool
    grex # [programming] regex generator
    gup # [programming] go binary installer/updater
    heaptrack # [programming] heap memory profiler
    heh # [programming] byte editor
    helm # [programming] kubernetes package manager
    help2man # [programming] generate man pages
    herdr-bin # [programming] AI agent terminal manager
    hermes-agent # [programming] AI agent
    hollywood # [programming] fake hacker terminal
    hotspot # [programming] Linux perf GUI
    hyperfine # [programming] command benchmarking tool
    jetbrains-toolbox # [programming] JetBrains IDE manager
    jless # [programming] JSON viewer TUI
    jnv # [programming] interactive JSON navigator
    jrnl # [programming] command-line journal
    jujutsu # [programming] git-compatible VCS
    jupyterlab # [programming] notebook IDE
    k9s # [programming] kubernetes TUI
    kubecolor # [programming] kubectl colorized output
    kubectl # [programming] kubernetes CLI
    kubectx # [programming] kubernetes context switcher
    lazydocker-bin # [programming] docker TUI
    lazygit # [programming] git TUI
    lazyjira-bin # [programming] jira tui
    lazyjj # [programming] jujutsu TUI
    lazymake # [programming] makefile TUI
    lazysql # [programming] SQL database TUI
    lcov # [programming] code coverage reports
    libvirt # [programming] libvirt
    libxslt # [programming] XSLT transform lib
    llvm # [programming] compiler infrastructure
    luarocks # [programming] Lua package manager
    make # [programming] build automation tool
    man-db # [programming] manual page database
    maven # [programming] Java build tool
    mdbook # [programming] markdown book generator
    mergiraf # [programming] merge conflict resolver
    mermaid-cli # [programming] diagram generator CLI
    meson # [programming] build system tool
    micro # [programming] terminal text editor
    miller # [programming] CSV/JSON data tool
    mingw-w64-gcc # [programming] Windows cross-compiler
    minikube # [programming] local kubernetes cluster
    mise # [programming] runtime version manager
    mold # [programming] fast linker
    nano # [programming] terminal text editor
    nasm # [programming] x86 assembler
    neovide # [programming] neovim GUI frontend
    neovim # [programming] modal text editor
    ninja # [programming] fast build system
    nix # [programming] Nix package manager
    nnd # [programming] linux debugger
    nodejs # [programming] JavaScript runtime
    npm # [programming] node package manager
    odin # [programming] Odin programming language
    oha # [programming] HTTP load testing
    onefetch # [programming] git repo summary
    opam # [programming] OCaml package manager
    openapi-tui # [programming] openapi tui
    opencomposite-git # [programming] OpenXR to OpenVR
    osmium-tool # [programming] OpenStreetMap data tool
    pastel # [programming] color manipulation CLI
    phoronix-test-suite # [programming] benchmarking suite
    pipeline-gtk # [programming] GStreamer pipeline debugger
    pkgconf # [programming] package compile flags
    postgresql # [programming] relational database
    postgresql-libs # [programming] postgres client libs
    posting # [programming] HTTP client TUI
    pre-commit # [programming] git hook manager
    prettier # [programming] code formatter
    python-black # [programming] Python code formatter
    python-faker # [programming] fake data generator
    python-isort # [programming] Python import sorter
    python-matplotlib # [programming] Python plotting library
    python-numba # [programming] Python JIT compiler
    python-numpy # [programming] numerical computing library
    python-pandas # [programming] data analysis library
    python-pillow # [programming] Python imaging library
    python-pip # [programming] Python package installer
    python-poetry # [programming] Python dependency manager
    python-pydantic # [programming] data validation library
    python-pygments # [programming] syntax highlighting library
    python-scikit-learn # [programming] machine learning library
    python-scipy # [programming] scientific computing library
    python-snakeviz # [programming] profiler visualization tool
    python-sympy # [programming] symbolic math library
    python-tree-sitter-html # [programming] HTML parser bindings
    python-tree-sitter-javascript # [programming] JS parser bindings
    python-tree-sitter-json # [programming] JSON parser bindings
    qbe # [programming] compiler backend
    qmk # [programming] keyboard firmware framework
    quickjs # [programming] embeddable JS engine
    r # [programming] R statistical language
    raddebugger-git # [programming] reverse debugger
    raylib # [programming] game programming library
    renderdoc # [programming] graphics frame debugger
    reptyr # [programming] reattach process to terminal
    resvg # [programming] SVG rendering librar
    rgx # [programming] regex testing
    ripgrep # [programming] fast recursive grep
    rstudio-desktop-bin # [programming] R development IDE
    rtk # [programming] tool compression
    samply # [programming] sampling profiler
    sccache # [programming] compiler cache tool
    sdl3 # [programming] multimedia/game library
    serpl # [programming] search-replace TUI tool
    skaffold # [programming] kubernetes dev workflow
    slides-git # [programming] terminal presentation tool
    speedscope # [programming] flamegraph profiler viewer
    sqlite # [programming] embedded SQL database
    sqlitebrowser # [programming] SQLite database GUI
    sqlx-cli # [programming] rust SQL migrations CLI
    strace-tui # [programming] strace-tui
    taskwarrior-tui # [programming] taskwarrior terminal UI
    terraform # [programming] infrastructure as code
    tesseract # [programming] OCR engine
    tesseract-data-deu # [programming] German OCR data
    tesseract-data-eng # [programming] English OCR data
    tig # [programming] git repository browser
    timew # [programming] time tracking CLI
    tokei # [programming] code line counter
    topology-toolkit # [programming] scalar field analysis
    tree-sitter-cli # [programming] incremental parser generator
    updo # [programming] website uptime monitor
    uv # [programming] fast Python package manager
    vscodium-bin # [programming] VS Code de-branded
    wrk # [programming] HTTP benchmarking tool
    wscat # [programming] websocket CLI client
    xh # [programming] friendly HTTP client
    xplr # [programming] terminal file picker
    yozefu # [programming] kafka browser TUI
    z3 # [programming] SMT theorem prover
    zed # [programming] collaborative code editor
    zig # [programming] Zig programming language
    zizmor # [programming] workflow auditing

    distrobox # [qemu] containerized distro tool
    gnome-boxes # [qemu] VM manager GUI
    qemu-full # [qemu] machine emulator/virtualizer
    virt-manager # [qemu] VM management GUI

    ollama-for-amd-git # [llm] local LLM runner (AMD)
    python-pytorch-rocm # [llm] ML framework (AMD)
    python-vllm-rocm # [llm] LLM serving (AMD)

    aircrack-ng # [pentesting] wifi security auditing
    ali # [pentesting] tui webapp load testing
    angryoxide # [pentesting] tui wifi pentesting
    argon2 # [pentesting] password hashing tool
    arjun # [pentesting] HTTP param discovery
    arp-scan # [pentesting] ARP network scanner
    bettercap # [pentesting] network attack framework
    binsider # [pentesting] binary analysis TUI
    bpftrace # [pentesting] eBPF tracing tool
    burpsuite # [pentesting] web security testing
    dalfox-bin # [pentesting] XSS scanning tool
    dsniff # [pentesting] network sniffing tools
    exploitdb # [pentesting] exploit database mirror
    fcrackzip # [pentesting] zip password cracker
    ffuf-bin # [pentesting] web fuzzing tool
    foremost # [pentesting] file carving tool
    gau # [pentesting] get-all-urls tool
    ghidra # [pentesting] reverse engineering suite
    gitleaks # [pentesting] git secrets scanner
    gobuster # [pentesting] directory/DNS brute-forcer
    gowitness-bin # [pentesting] web screenshot tool
    gufw # [pentesting] firewall GUI (ufw)
    hashcat # [pentesting] password cracking tool
    hping # [pentesting] packet crafting tool
    httpx-bin # [pentesting] HTTP probing tool
    hydra # [pentesting] login brute-forcer
    hysteria # [pentesting] proxy/tunnel tool
    i2pd # [pentesting] I2P network daemon
    john # [pentesting] password cracker
    katana-bin # [pentesting] web crawling tool
    kismet # [pentesting] wireless network detector
    kiterunner-bin # [pentesting] API endpoint bruteforcer
    lynis # [pentesting] security auditing tool
    mdk4 # [pentesting] wifi attack toolkit
    metasploit # [pentesting] exploitation framework
    mitmproxy # [pentesting] HTTPS intercepting proxy
    mkcert # [pentesting] local TLS certificates
    naabu-bin # [pentesting] port scanning tool
    netscanner # [pentesting] network scanning TUI
    nftables # [pentesting] firewall packet filter
    nikto # [pentesting] web server scanner
    nmap # [pentesting] network mapper scanner
    nuclei-bin # [pentesting] vulnerability scanner
    nuclei-templates # [pentesting] nuclei scan templates
    obfs4proxy # [pentesting] Tor traffic obfuscator
    openvpn # [pentesting] VPN client/server
    osslsigncode # [pentesting] authenticode signing tool
    pwdsafety # [pentesting] pwd checking
    pwndbg # [pentesting] GDB exploit-dev plugin
    python-pwntools # [pentesting] exploit development library
    reaver-wps-fork-t6x-git # [pentesting] WPS PIN cracker
    rkhunter # [pentesting] rootkit detection tool
    rz-cutter # [pentesting] reverse engineering GUI
    seclists # [pentesting] security wordlists collection
    skipfish # [pentesting] web app security scanner
    slowhttptest # [pentesting] DoS testing tool
    sops # [pentesting] secrets encryption tool
    sqlmap-git # [pentesting] SQL injection tool
    sslscan # [pentesting] TLS/SSL cipher scanner
    subfinder-bin # [pentesting] subdomain discovery tool
    testssl.sh # [pentesting] TLS/SSL testing script
    tor-router # [pentesting] transparent tor routing
    trivy # [pentesting] container vulnerability scanner
    trufflehog # [pentesting] secrets scanning tool
    valgrind # [pentesting] memory debugging tool
    veil-bin # [pentesting] antivirus evasion framework
    veracrypt # [pentesting] disk encryption tool
    volatility3-git # [pentesting] memory forensics framework
    wafw00f # [pentesting] WAF fingerprinting tool
    wireguard-tools # [pentesting] WireGuard VPN tools
    wireguard-ui-bin # [pentesting] WireGuard web UI
    wireshark-qt # [pentesting] network protocol analyzer
    zaproxy # [pentesting] OWASP ZAP scanner

)
FLATPAK_PKGS=(
    com.jeffser.Alpaca # [programming] Ollama chat GUI
)

CARGO_PKGS=(
    tmux-sessionizer # [base] tmux project sessionizer

    bootimage # [programming] bootable kernel images
    cargo-afl # [programming] AFL fuzzing rust
    cargo-info # [programming] crate info lookup
    cargo-leptos # [programming] leptos framework build
    cargo-nextest # [programming] faster rust test runner
    cargo-seek # [programming] crates.io search tool
    cargo-shear # [programming] unused deps detector
    cargo-xbuild # [programming] cross-compile core std
    irust # [programming] rust REPL shell
    kani-verifier # [programming] rust formal verifier
    lean-tui # [programming] Lean theorem prover TUI
    leptosfmt # [programming] leptos code formatter
    rustfilt # [programming] rust symbol demangler
    tauri-cli # [programming] tauri app CLI
)

CARGO_PKGS_GIT=(
)

GO_PKGS=(
    github.com/felangga/chiko/cmd/chiko@latest # [programming] gRPC TUI client
    github.com/litescript/ls-horizons/cmd/ls-horizons@latest # [programming] deep space network tracker
    github.com/zdyxry/tokui@latest # [programming] code stats TUI
)

NIX_PKGS=(
    nixpkgs#devenv # [programming] reproducible dev environments
)

## PACKAGE GROUPS

GROUPS_STATE="$HOME/projects/arch-dotfiles/groups.conf"
PKG_GROUPS=(base fonts desktop socials gaming creating latex programming qemu llm pentesting)

if [[ ! -f "$GROUPS_STATE" ]]; then
    if [[ -t 0 ]]; then
        echo "Select package groups to install (space-separated numbers, or press enter for all):"
        for i in "${!PKG_GROUPS[@]}"; do
            echo "  $(( i + 1 ))  ${PKG_GROUPS[i]}"
        done
        echo "  0  all groups"
        echo ""
        read -rp "Enter numbers (e.g. '1 3 5' or '0' for all): " -a nums
        if [[ ${#nums[@]} -gt 0 && "${nums[0]}" != "0" ]]; then
            selected=()
            for n in "${nums[@]}"; do
                if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 && n <= ${#PKG_GROUPS[@]} )); then
                    selected+=("${PKG_GROUPS[n-1]}")
                fi
            done
            if [[ ${#selected[@]} -gt 0 ]]; then
                printf '%s\n' "${selected[@]}" > "$GROUPS_STATE"
            else
                printf '%s\n' "${PKG_GROUPS[@]}" > "$GROUPS_STATE"
            fi
        else
            printf '%s\n' "${PKG_GROUPS[@]}" > "$GROUPS_STATE"
        fi
    else
        printf '%s\n' "${PKG_GROUPS[@]}" > "$GROUPS_STATE"
    fi
    echo "Enabled groups:" >&2
    cat "$GROUPS_STATE" >&2
fi
ENABLED_GROUPS=$(cat "$GROUPS_STATE")

filter_by_group() {
    awk -v arr="$1" -v groups="$ENABLED_GROUPS" '
        BEGIN { n = split(groups, g, "\n") }
        $0 ~ "^" arr "=\\(" { f=1; next }
        f && /^\)/ { f=0 }
        f {
            for (i = 1; i <= n; i++) {
                if (index($0, "[" g[i] "]") > 0) {
                    pkg=$1; gsub(/^[ \t]+|[ \t]+$/, "", pkg)
                    if (pkg != "") print pkg
                    break
                }
            }
        }
    ' "$(pwd)/install.sh"
}

mapfile -t PACKAGES < <(filter_by_group PACKAGES)
mapfile -t FLATPAK_PKGS < <(filter_by_group FLATPAK_PKGS)
mapfile -t CARGO_PKGS < <(filter_by_group CARGO_PKGS)
mapfile -t CARGO_PKGS_GIT < <(filter_by_group CARGO_PKGS_GIT)
mapfile -t GO_PKGS < <(filter_by_group GO_PKGS)
mapfile -t NIX_PKGS < <(filter_by_group NIX_PKGS)

## BOOT DISK SECURITY (timeshift btrfs snapshots, Secure Boot, LUKS)

# Partitioning/bootloader is already done by the time install.sh runs (see
# l-dotfiles convention), so this only detects what the existing layout
# supports and configures it — it never repartitions, converts MBR→GPT, or
# migrates an unencrypted install into LUKS. See README §Boot disk security
# and BOOT.md for the manual steps those require.
BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
BOOT_FEATURES=(timeshift sbctl luks)

if [[ ! -f "$BOOT_STATE" ]]; then
    if [[ -t 0 ]]; then
        echo ""
        echo "Boot disk security (timeshift/sbctl/luks) — each is detected and"
        echo "skipped automatically if this system's layout doesn't support it"
        echo "yet (see README §Boot disk security for how to prepare it):"
        for i in "${!BOOT_FEATURES[@]}"; do
            echo "  $(( i + 1 ))  ${BOOT_FEATURES[i]}"
        done
        echo "  0  all"
        echo ""
        read -rp "Enter numbers to attempt (e.g. '1 2' or '0' for all, enter for none): " -a bnums
        selected=()
        if [[ ${#bnums[@]} -gt 0 && "${bnums[0]}" == "0" ]]; then
            selected=("${BOOT_FEATURES[@]}")
        else
            for n in "${bnums[@]}"; do
                if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 && n <= ${#BOOT_FEATURES[@]} )); then
                    selected+=("${BOOT_FEATURES[n-1]}")
                fi
            done
        fi
        printf '%s\n' "${selected[@]}" > "$BOOT_STATE"
    else
        : > "$BOOT_STATE" # non-interactive: opt-in only, nothing enabled by default
    fi
    echo "Enabled boot features:" >&2
    cat "$BOOT_STATE" >&2
fi

## REMOVE PASSWORD FROM SUDO

# A drop-in, not an append to /etc/sudoers. The guard used to be
# `grep -q '$USER'` in SINGLE quotes, so it searched for the literal string
# `$USER`, never matched the expanded line it had written, and appended one more
# `NOPASSWD: ALL` on every run — eight of them on this machine before anyone
# looked. A file in sudoers.d is idempotent by construction: same path, same
# content, one rule.
#
# Written via a temp file and `visudo -c` before install: a syntax error in
# /etc/sudoers.d locks every user out of sudo on the next invocation, and the
# recovery for that is a root shell you may not have.
SUDOERS_DROPIN="/etc/sudoers.d/10-arch-dotfiles-nopasswd"
sudo_tmp="$(mktemp)"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER" > "$sudo_tmp"
if sudo visudo -c -f "$sudo_tmp" >/dev/null 2>&1; then
    sudo install -m440 -o root -g root "$sudo_tmp" "$SUDOERS_DROPIN"
else
    echo "sudoers drop-in failed validation — left unchanged" >&2
    echo "sudoers NOPASSWD drop-in" >> "$FAILURES_FILE"
fi
rm -f "$sudo_tmp"

# CLEAN UP AFTER THE OLD BUG. Fixing the guard stops new duplicates; it does
# nothing about the ones already appended to /etc/sudoers on every machine that
# ran the broken version. The rule now lives in the drop-in above, so those
# lines are redundant — and a pile of identical NOPASSWD entries in the main
# file is exactly the kind of thing nobody reads until it matters.
#
# ONLY the exact line the old code wrote is removed, matched whole:
#   <user> ALL=(ALL) NOPASSWD: ALL
# Anything hand-written, differently spaced, or scoped to specific commands is
# left alone — this is not the place to be clever about someone's sudo policy.
#
# The edit happens on a copy, is validated with `visudo -c`, and is only
# installed if validation passes and the drop-in that replaces the rule is
# actually in place. A broken /etc/sudoers means no sudo at all, and the
# recovery is a root shell you may not have.
if [[ -f "$SUDOERS_DROPIN" ]] && sudo grep -qE "^${USER}[[:space:]]+ALL=\(ALL\)[[:space:]]+NOPASSWD:[[:space:]]+ALL[[:space:]]*$" /etc/sudoers 2>/dev/null; then
    sudoers_tmp="$(mktemp)"
    sudo cat /etc/sudoers > "$sudoers_tmp"
    dupes="$(grep -cE "^${USER}[[:space:]]+ALL=\(ALL\)[[:space:]]+NOPASSWD:[[:space:]]+ALL[[:space:]]*$" "$sudoers_tmp" || true)"
    sed -i -E "/^${USER}[[:space:]]+ALL=\(ALL\)[[:space:]]+NOPASSWD:[[:space:]]+ALL[[:space:]]*$/d" "$sudoers_tmp"
    if sudo visudo -c -f "$sudoers_tmp" >/dev/null 2>&1; then
        sudo install -m440 -o root -g root /etc/sudoers /etc/sudoers.arch-dotfiles-backup
        sudo install -m440 -o root -g root "$sudoers_tmp" /etc/sudoers
        echo "sudoers: removed $dupes duplicate NOPASSWD line(s) from /etc/sudoers (rule is now in $SUDOERS_DROPIN; backup at /etc/sudoers.arch-dotfiles-backup)" >&2
    else
        echo "sudoers: cleanup of duplicate NOPASSWD lines failed validation — /etc/sudoers left untouched" >&2
        echo "sudoers duplicate-line cleanup" >> "$FAILURES_FILE"
    fi
    rm -f "$sudoers_tmp"
fi

## LINK PACMAN CONFIG

# chaotic aur
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm

pushd ./configs/pacman
( set -o pipefail; sh ./link.sh 2>&1 | tee ./link.sh.log ) || echo "configs/pacman/link.sh" >> "$FAILURES_FILE"
popd

## INSTALLING ALL THE THINGS

# update. One -Syyu for the whole run; -Sy/-Syy inside install commands is
# what made reruns slow (each refresh re-downloads the DB and hits mirror
# rate limits). Everything below installs with --needed, which skips
# packages that are already installed and current, so a rerun of this
# script costs seconds, not a full reinstall.
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Syyu --noconfirm

# install yay (skipped when already present)
if ! command -v yay >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    ( cd yay && makepkg -si --noconfirm )
    rm -rf yay/
fi

# force rustup and stable, since a lot of packages would otherwise install rust and conflict
sudo pacman -S --needed --noconfirm rustup
rustup toolchain install nightly || true
rustup toolchain install stable || true
rustup default stable || true

# install all the things. ONE pacman/paru transaction instead of one per
# group: paru resolves the full dep set at once and a single -Sy-free run
# avoids per-chunk mirror refreshes/rate limits. --needed keeps reruns
# idempotent (already-installed packages are skipped, not reinstalled).
export yay_skipcheck=true # prevent failing tests to break everything
if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    retry 5 yay -S --needed --noconfirm --mflags --skipinteg "${PACKAGES[@]}" \
        || echo "yay batch (${#PACKAGES[@]} pkgs)" >> "$FAILURES_FILE"
fi

if [[ ${#CARGO_PKGS[@]} -gt 0 ]]; then
    cargo install --locked "${CARGO_PKGS[@]}" -j $(nproc) \
        || echo "cargo batch" >> "$FAILURES_FILE"
fi
for git_pkg in "${CARGO_PKGS_GIT[@]}"; do
    cargo install --git "$git_pkg" -j $(nproc) || echo "cargo $git_pkg" >> "$FAILURES_FILE"
done

if [[ ${#GO_PKGS[@]} -gt 0 ]]; then
    # `go install a@latest b@latest` fails with "all packages must be provided
    # by the same module" — versioned installs only work one module at a time.
    for go_pkg in "${GO_PKGS[@]}"; do
        go install "$go_pkg" || echo "go $go_pkg" >> "$FAILURES_FILE"
    done
fi
if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then
    flatpak install flathub -y "${FLATPAK_PKGS[@]}" \
        || echo "flatpak batch" >> "$FAILURES_FILE"
fi
if [[ ${#NIX_PKGS[@]} -gt 0 ]]; then
    nix profile install --extra-experimental-features 'nix-command flakes' "${NIX_PKGS[@]}" \
        || echo "nix batch" >> "$FAILURES_FILE"
fi

# cleanup
rm -rf ${HOME}/.cache/yay/
sudo rm -rf ${HOME}/go/

## LINK

echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config"      | sudo tee -a /etc/security/pam_env.conf
echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache"       | sudo tee -a /etc/security/pam_env.conf
echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf

while IFS= read -r script; do
    dir=$(dirname "$script"); base=$(basename "$script")
    ( set -o pipefail; cd "$dir" && sh "$base" </dev/null 2>&1 | tee "${script}.log" ) || echo "$script" >> "$FAILURES_FILE"
done < <(find "$(pwd)" -type f -name 'link.sh')
while IFS= read -r script; do
    dir=$(dirname "$script"); base=$(basename "$script")
    ( set -o pipefail; cd "$dir" && python "$base" </dev/null 2>&1 | tee "${script}.log" ) || echo "$script" >> "$FAILURES_FILE"
done < <(find "$(pwd)" -type f -name 'link.py')

## LFS PULL

git lfs pull

## INIT WALLPAPER AND THEME FILES

# First run must land on the default theme, not a re-derived palette:
# mountain2.jpg is ayu-dark.json's own wallpaper (its "wallpaper" field
# points here), so switch-wallpaper.sh matches the theme JSON and applies
# the hand-authored ayu-dark palette via `wallust cs` instead of
# re-extracting colors from the image.
./scripts/switch-wallpaper.sh ./wallpapers/mountain2.jpg >/dev/null 2>/dev/null || \
    echo "scripts/switch-wallpaper.sh" >> "$FAILURES_FILE"

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

# Bootstrap nvim plugins headlessly before ever showing a GUI window: on a
# fresh install lazy.nvim would otherwise install everything the first time
# a human happens to open nvim interactively, racing the unattended reboot
# 150s above. `Lazy! sync` clones every plugin synchronously; matches
# configs/emacs/link.sh's equivalent batch bootstrap for parity between the
# two editors on a fresh machine.
if command -v nvim >/dev/null 2>&1; then
    nvim --headless "+Lazy! sync" +qa || echo "nvim plugin bootstrap" >> "$FAILURES_FILE"
fi

nvim &
