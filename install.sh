#!/usr/bin/env bash
# Stage 2: every package of the platform's groups, compiled ones prebuilt from mirror.lsck0.dev

set -e

# progress bars need a tty: re-exec under `script` so pacman/yay render live while logging, plain tee without one
if [ -z "${_PTY_LOG:-}" ]; then
    export _PTY_LOG=1
    # before the re-exec, whose pty stdin would look like a person even under stage.sh's </dev/null
    [ -t 0 ] || export DOTFILES_UNATTENDED=1
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        exec script -qe -c "$0 $*" install.log
    fi
    exec > >(tee install.log) 2>&1
fi

export FAILURES_FILE="$PWD/FAILURES.install"
: >"$FAILURES_FILE"

# stage.sh retries an abort but moves on from a run that only logged failures
EXIT_FAILURES=1
EXIT_ABORTED=2
install_finished=0
on_exit() {
    ((install_finished)) || exit "$EXIT_ABORTED"
}
trap on_exit EXIT

## PACKAGES

PACKAGES=(
    alsa-firmware                     # [hardware] ALSA sound firmware
    amd-ucode                         # [hardware] AMD CPU microcode, pacstrap installs it on AMD
    apparmor                          # [hardware] mandatory access control LSM, parser and stock profiles
    apparmor.d                        # [hardware] aa-install and the browser/discord/zathura profiles (configs/apparmor)
    bluetui                           # [hardware] bluetooth tui
    bluez                             # [hardware] bluetooth stack
    bluez-obex                        # [hardware] bluetooth OBEX (file transfer)
    bluez-utils                       # [hardware] bluetooth utilities
    btrfs-progs                       # [hardware] btrfs filesystem tools
    cryptsetup                        # [hardware] LUKS tooling, pacstrap installs it
    cups                              # [hardware] printing system
    cups-pdf                          # [hardware] print-to-PDF virtual printer
    efibootmgr                        # [hardware] EFI boot manager
    fail2ban                          # [hardware] intrusion prevention tool
    fwupd                             # [hardware] lvfs firmware updates (nvme, gpu, usb4, uefi dbx)
    grub                              # [hardware] bootloader, pacstrap installs it
    intel-media-driver                # [hardware] Intel VAAPI driver
    intel-ucode                       # [hardware] Intel CPU microcode, pacstrap installs it on Intel
    jolt                              # [hardware] battery debugging
    lact                              # [hardware] AMD GPU control: power limit, fan curve, undervolt
    lib32-vulkan-radeon               # [hardware] 32-bit AMD Vulkan
    libinput-tools                    # [hardware] libinput debug tools
    libva-utils                       # [hardware] vainfo, verify gpu codec support
    linux                             # [hardware] Linux kernel
    linux-firmware                    # [hardware] kernel firmware blobs
    linux-headers                     # [hardware] kernel headers
    linux-lts                         # [hardware] long-term-support kernel
    linux-lts-headers                 # [hardware] LTS kernel headers
    linux-tools-meta                  # [hardware] kernel perf tools
    lm_sensors                        # [hardware] hardware sensors, ships fancontrol/pwmconfig/sensors-detect
    mkinitcpio                        # [hardware] initramfs generator, pacstrap installs it
    modemmanager                      # [hardware] mobile broadband (WWAN), toggle-mobile
    networkmanager                    # [hardware] network connection manager
    nftables                          # [hardware] firewall packet filter
    os-prober                         # [hardware] other systems in grub's menu (GRUB_DISABLE_OS_PROBER=false)
    pipewire                          # [hardware] audio/video server
    pipewire-alsa                     # [hardware] pipewire ALSA compat
    pipewire-pulse                    # [hardware] pipewire pulse compat
    plymouth                          # [hardware] boot splash screen
    portmaster-bin                    # [hardware] application firewall
    python-evdev                      # [hardware] input events for the configs/tablet userspace driver
    sane                              # [hardware] scanner access library
    sbctl                             # [hardware] Secure Boot key management
    scx-scheds                        # [hardware] sched_ext perf schedulers
    smartmontools                     # [hardware] disk health monitoring
    sof-firmware                      # [hardware] sound open firmware
    thermald                          # [hardware] thermal management daemon
    timeshift                         # [hardware] system backup/restore
    timeshift-autosnap                # [hardware] pacman hook for pre-upgrade snapshots
    tlp                               # [hardware] laptop power management
    tor-router                        # [hardware] transparent tor routing, toggles/toggle-tor.sh
    v4l-utils                         # [hardware] video4linux utilities
    v4l2loopback-dkms                 # [hardware] virtual video device
    v4l2loopback-utils                # [hardware] v4l2loopback helper tools
    vulkan-intel                      # [hardware] Intel Vulkan driver
    vulkan-nouveau                    # [hardware] Nvidia open Vulkan
    vulkan-radeon                     # [hardware] AMD Vulkan driver
    wireless-regdb                    # [hardware] wifi regulatory db the kernel loads
    wpa_supplicant                    # [hardware] wifi authentication daemon
    zram-generator                    # [hardware] compressed swap generator

    age                               # [base] file encryption, opens the YubiKey-sealed secrets key
    age-plugin-yubikey                # [base] age identities in the YubiKey PIV applet
    app2unit                          # [base] app to systemd unit
    argon2                            # [base] password hashing tool
    base                              # [base] Arch base group
    base-devel                        # [base] Arch build tools
    borg                              # [base] deduplicating backup tool
    bpftop                            # [base] bpf monitor
    btop                              # [base] resource monitor TUI
    bubblewrap                        # [base] unprivileged sandbox, runs untrusted binaries without network
    caligula                          # [base] disk imaging tool
    ccid                              # [base] smartcard CCID driver (YubiKey OpenPGP)
    chafa                             # [base] terminal image renderer
    cifs-utils                        # [base] SMB/CIFS mount tools
    clonezilla                        # [base] disk cloning tool
    cmatrix                           # [base] matrix terminal animation
    coreutils                         # [base] GNU core utilities
    cowsay                            # [base] ascii cow sayings
    cpufetch                          # [base] CPU info fetcher
    croc                              # [base] secure file transfer
    cronie                            # [base] cron daemon
    curl                              # [base] HTTP client tool
    czmq-git                          # [base] libczmq for ossec-hids-local, which links it without depending on it
    diskwatch                         # [base] disk debugging
    dog                               # [base] DNS lookup tool
    downgrade                         # [base] pacman package downgrader
    dua-cli                           # [base] disk usage analyzer
    dwarfs                            # [base] compressed read-only fs
    dysk                              # [base] disk usage viewer
    eza                               # [base] modern ls replacement
    fastfetch                         # [base] system info fetcher
    fd                                # [base] find alternative
    ffmpeg                            # [base] audio/video converter
    file                              # [base] file type detector
    flatpak                           # [base] sandboxed app packages
    freetype2                         # [base] font rasterizer
    fzf                               # [base] fuzzy finder
    fzf-tab-git                       # [base] fzf for zsh tab completion
    ghostmirror                       # [base] mirrorlist ranking tool
    git                               # [base] version control
    git-crypt                         # [base] transparent encryption of the secrets repo
    gnutls                            # [base] TLS library
    gpg-tui                           # [base] gpg tui
    gping                             # [base] ping with graph
    gum                               # [base] pretty shell prompts/inputs
    imagemagick                       # [base] theme generator dependency
    ipython                           # [base] enhanced Python shell
    jq                                # [base] JSON processor CLI
    just                              # [base] command runner
    kmon                              # [base] kernel monitor
    knockd                            # [base] port-knock client (knock) for hidden sshd
    lazyjournal                       # [base] journalctl/log TUI
    less                              # [base] pager utility
    libappimage                       # [base] AppImage runtime lib
    libev                             # [base] event loop library
    libfido2                          # [base] FIDO2/U2F device library
    libgcrypt                         # [base] crypto library
    libgpg-error                      # [base] gpg error codes
    libjpeg-turbo                     # [base] JPEG codec library
    libldap                           # [base] LDAP client library
    libpng                            # [base] PNG image library
    libpqxx                           # [base] C++ postgres client
    libpulse                          # [base] PulseAudio client lib
    libva                             # [base] VAAPI video accel
    libvips                           # [base] image processing library
    libxcomposite                     # [base] X composite extension
    libxinerama                       # [base] X multi-monitor lib
    lolcat                            # [base] rainbow text output
    lshw                              # [base] hardware lister
    lua51-luautf8                     # [base] Lua UTF-8 lib
    lynis                             # [base] security auditing tool
    man-pages                         # [base] Linux manual pages
    mesa                              # [base] graphics driver library
    mtools                            # [base] DOS filesystem tools
    mtr                               # [base] traceroute + ping
    ncurses                           # [base] terminal UI library
    nss-mdns                          # [base] mDNS name resolution
    ntfs-3g                           # [base] NTFS filesystem driver
    nushell                           # [base] structured-data shell
    oh-my-zsh-git                     # [base] zsh libs and plugins, sourced without the framework
    openal                            # [base] 3D audio library
    openbsd-netcat                    # [base] netcat networking tool
    opencl-icd-loader                 # [base] OpenCL loader
    openssh                           # [base] SSH client/server
    openssl                           # [base] TLS/crypto toolkit
    openvpn                           # [base] VPN client/server
    ossec-hids-local                  # [base] host intrusion detection
    ouch                              # [base] archive compression tool
    pacman-contrib                    # [base] pacman cache cleanup tools
    pam-u2f                           # [base] FIDO2/U2F PAM module (YubiKey touch auth)
    pandoc-cli                        # [base] document format converter
    parallel                          # [base] run commands in parallel
    pass                              # [base] CLI password manager
    pass-otp                          # [base] pass TOTP/2FA extension
    pcsclite                          # [base] PC/SC smartcard middleware
    pdftk                             # [base] PDF toolkit
    procs                             # [base] modern ps replacement
    proton-vpn-cli                    # [base] ProtonVPN CLI (protonvpn command)
    python                            # [base] theme generator scripts
    python-pywalfox                   # [base] firefox theme propagator
    rar                               # [base] RAR archive tool
    rkhunter                          # [base] rootkit detection tool
    rsync                             # [base] file sync tool
    rustnet                           # [base] network monitor TUI
    rustup                            # [base] rust toolchain manager, installed before the batch so nothing pulls rust
    s-tui                             # [base] CPU stress/monitor TUI
    sd                                # [base] sed alternative CLI
    socat                             # [base] socket relay tool
    sshfs                             # [base] SSH filesystem mount
    sshpass                           # [base] non-interactive SSH auth
    starship                          # [base] cross-shell prompt
    sudo                              # [base] privilege escalation tool
    superseedr                        # [base] terminal torrent
    syncthing                         # [base] file sync daemon
    tailspin                          # [base] logging tool
    tar                               # [base] archiving utility
    tar-scripts                       # [base] tar helper scripts
    themix-gui-git                    # [base] GTK theme exporter
    themix-plugin-base16-git          # [base] themix export plugin
    tk                                # [base] Tcl/Tk GUI toolkit
    tldr                              # [base] simplified man pages
    tmux                              # [base] terminal multiplexer
    tmux-fingers                      # [base] tmux copy-paste hints
    tmux-sessionizer                  # [base] tmux project sessionizer
    tparted-bin                       # [base] partitioning TUI tool
    traceroute                        # [base] network route tracer
    trash-cli                         # [base] CLI trash bin
    trippy                            # [base] traceroute + ping TUI
    tty-clock                         # [base] terminal clock display
    unzip                             # [base] zip extraction tool
    usbtree                           # [base] usb tui
    ventoy-bin                        # [base] multi-boot USB creator
    veracrypt                         # [base] disk encryption tool
    vim                               # [base] modal text editor
    vulkan-icd-loader                 # [base] Vulkan loader library
    wallust-git                       # [base] wallpaper colour engine
    wget                              # [base] file download utility
    whois                             # [base] domain lookup tool
    wiki-tui                          # [base] Wikipedia terminal browser
    wireguard-tools                   # [base] WireGuard VPN tools
    xdg-ninja                         # [base] XDG compliance checker
    xdg-user-dirs                     # [base] standard user directories
    xdg-utils                         # [base] desktop integration utilities
    xorg-server-xvfb                  # [base] virtual display for themix-multi-export while config.sh runs headless
    yay                               # [base] AUR helper
    yazi                              # [base] terminal file manager
    yt-dlp                            # [base] video downloader
    yubikey-manager                   # [base] ykman: OpenPGP/PIV/OATH/OTP config
    yubikey-personalization           # [base] ykpersonalize: static-pw/chalresp slots
    zip                               # [base] zip archiving tool
    zoxide                            # [base] smarter cd command
    zsh                               # [base] Z shell
    zsh-autosuggestions               # [base] zsh history suggestions
    zsh-completions                   # [base] extra zsh completions
    zsh-syntax-highlighting           # [base] zsh command line highlighting

    noto-fonts                        # [fonts] Google Noto fonts
    noto-fonts-emoji                  # [fonts] Noto emoji fonts
    noto-fonts-extra                  # [fonts] Noto extra fonts
    otf-atkinsonhyperlegiblemono-nerd # [fonts] Atkinson Hyperlegible Mono Nerd Font
    otf-aurulent-nerd                 # [fonts] Aurulent Sans Nerd Font
    otf-codenewroman-nerd             # [fonts] Code New Roman Nerd Font
    otf-comicshanns-nerd              # [fonts] Comic Shanns Nerd Font
    otf-commit-mono-nerd              # [fonts] Commit Mono Nerd Font
    otf-droid-nerd                    # [fonts] Droid Sans Mono Nerd Font
    otf-firamono-nerd                 # [fonts] Fira Mono Nerd Font
    otf-geist-mono-nerd               # [fonts] Geist Mono Nerd Font
    otf-hasklig-nerd                  # [fonts] Hasklig Nerd Font
    otf-hermit-nerd                   # [fonts] Hermit Nerd Font
    otf-monaspace-nerd                # [fonts] MonoSpace Nerd Font
    otf-opendyslexic-nerd             # [fonts] OpenDyslexic Nerd Font
    otf-overpass-nerd                 # [fonts] Overpass Nerd Font
    powerline-fonts                   # [fonts] powerline symbol fonts
    terminus-font-ttf                 # [fonts] bitmap terminal font
    ttf-0xproto-nerd                  # [fonts] 0xProto Nerd Font
    ttf-3270-nerd                     # [fonts] 3270 Nerd Font
    ttf-adwaitamono-nerd              # [fonts] Adwaita Mono Nerd Font
    ttf-agave-nerd                    # [fonts] Agave Nerd Font
    ttf-annotationmono-nerd           # [fonts] Annotation Mono Nerd Font
    ttf-anonymous-pro                 # [fonts] monospace font
    ttf-anonymouspro-nerd             # [fonts] Anonymous Pro Nerd Font
    ttf-arimo-nerd                    # [fonts] Arimo Nerd Font
    ttf-arphic-ukai                   # [fonts] Chinese kai font
    ttf-arphic-uming                  # [fonts] Chinese ming font
    ttf-atkinson-hyperlegible         # [fonts] accessible reading font
    ttf-baekmuk                       # [fonts] Korean font family
    ttf-bigblueterminal-nerd          # [fonts] Big Blue Terminal Nerd Font
    ttf-bitstream-vera-mono-nerd      # [fonts] Bitstream Vera Mono Nerd Font
    ttf-caladea                       # [fonts] Cambria-metric font
    ttf-cascadia-code                 # [fonts] monospace coding font
    ttf-cascadia-code-nerd            # [fonts] CaskaydiaCove Nerd Font
    ttf-cascadia-mono-nerd            # [fonts] Cascadia Mono Nerd Font
    ttf-cormorant                     # [fonts] serif display font
    ttf-cousine-nerd                  # [fonts] Cousine Nerd Font
    ttf-crimson                       # [fonts] serif text font
    ttf-crimson-pro                   # [fonts] serif text font
    ttf-crimson-pro-variable          # [fonts] variable serif font
    ttf-croscore                      # [fonts] Chrome OS fonts
    ttf-d2coding-nerd                 # [fonts] D2Coding Nerd Font
    ttf-daddytime-mono-nerd           # [fonts] DaddyTime Mono Nerd Font
    ttf-dejavu-nerd                   # [fonts] DejaVu Nerd Font
    ttf-doulos-sil                    # [fonts] phonetic Unicode font
    ttf-droid                         # [fonts] Android system fonts
    ttf-envycoder-nerd                # [fonts] EnvyCoder Nerd Font
    ttf-eurof                         # [fonts] Eurostile-style font
    ttf-fantasque-nerd                # [fonts] Fantasque Sans Mono Nerd Font
    ttf-fantasque-sans-mono           # [fonts] quirky monospace font
    ttf-fira-code                     # [fonts] ligature coding font
    ttf-fira-mono                     # [fonts] monospace font
    ttf-fira-sans                     # [fonts] humanist sans font
    ttf-firacode-nerd                 # [fonts] FiraCode Nerd Font
    ttf-gentium                       # [fonts] serif Unicode font
    ttf-gentium-book                  # [fonts] serif book font
    ttf-gentium-plus                  # [fonts] extended serif font
    ttf-go-nerd                       # [fonts] Go Nerd Font
    ttf-gohu-nerd                     # [fonts] Gohu Nerd Font
    ttf-googlesanscode-nerd           # [fonts] Google Sans Code Nerd Font
    ttf-hack                          # [fonts] monospace coding font
    ttf-hack-nerd                     # [fonts] Hack Nerd Font
    ttf-hanazono                      # [fonts] Japanese CJK font
    ttf-hannom                        # [fonts] Vietnamese Han-Nom font
    ttf-heavydata-nerd                # [fonts] Heavy Data Nerd Font
    ttf-iawriter-nerd                 # [fonts] iA Writer Nerd Font
    ttf-ibm-plex                      # [fonts] IBM typeface family
    ttf-ibmplex-mono-nerd             # [fonts] IBM Plex Mono Nerd Font
    ttf-inconsolata                   # [fonts] monospace coding font
    ttf-inconsolata-go-nerd           # [fonts] Inconsolata Go Nerd Font
    ttf-inconsolata-lgc-nerd          # [fonts] Inconsolata LGC Nerd Font
    ttf-inconsolata-nerd              # [fonts] Inconsolata Nerd Font
    ttf-indic-otf                     # [fonts] Indic script fonts
    ttf-input                         # [fonts] coding-focused font
    ttf-input-nerd                    # [fonts] Input font + icons
    ttf-intone-nerd                   # [fonts] Intone Nerd Font
    ttf-iosevka-nerd                  # [fonts] Iosevka Nerd Font
    ttf-iosevkaterm-nerd              # [fonts] Iosevka Term Nerd Font
    ttf-iosevkatermslab-nerd          # [fonts] Iosevka Term SLAB Nerd Font
    ttf-jetbrains-mono                # [fonts] monospace coding font
    ttf-jetbrains-mono-nerd           # [fonts] JetBrains Mono Nerd Font
    ttf-jigmo                         # [fonts] rare CJK glyphs
    ttf-junicode                      # [fonts] medievalist Unicode font
    ttf-junicode-variable             # [fonts] variable medievalist font
    ttf-khmer                         # [fonts] Khmer script font
    ttf-lato                          # [fonts] humanist sans font
    ttf-lekton-nerd                   # [fonts] Lekton Nerd Font
    ttf-liberation-mono-nerd          # [fonts] Liberation Mono Nerd Font
    ttf-libertinus                    # [fonts] classic serif family
    ttf-lilex-nerd                    # [fonts] Lilex Nerd Font
    ttf-linux-libertine               # [fonts] free serif font
    ttf-linux-libertine-g             # [fonts] Libertine with graphite
    ttf-martian-mono-nerd             # [fonts] Martian Mono Nerd Font
    ttf-material-icons                # [fonts] material design icons
    ttf-material-symbols-variable     # [fonts] variable material icons
    ttf-meslo-nerd                    # [fonts] Meslo Nerd Font
    ttf-mona-sans                     # [fonts] GitHub display font
    ttf-monaspace-frozen              # [fonts] GitHub monospace font
    ttf-monaspace-variable            # [fonts] variable monospace font
    ttf-monocraft-git                 # [fonts] Minecraft-style monospace
    ttf-monofur                       # [fonts] futuristic monospace font
    ttf-monofur-nerd                  # [fonts] MonoFur Nerd Font
    ttf-monoid                        # [fonts] coding-focused monospace
    ttf-monoid-nerd                   # [fonts] Monoid Nerd Font
    ttf-mononoki-nerd                 # [fonts] Mononoki Nerd Font
    ttf-montserrat                    # [fonts] geometric sans font
    ttf-mplus-nerd                    # [fonts] Mplus Nerd Font
    ttf-ms-fonts                      # [fonts] Microsoft core fonts
    ttf-nerd-fonts-symbols            # [fonts] Nerd Fonts Symbols
    ttf-nerd-fonts-symbols-mono       # [fonts] Nerd Fonts Symbols Mono
    ttf-noto-nerd                     # [fonts] Noto Nerd Font
    ttf-nunito                        # [fonts] rounded sans font
    ttf-opensans                      # [fonts] humanist sans font
    ttf-overpass                      # [fonts] highway-gothic sans font
    ttf-profont-nerd                  # [fonts] ProFont Nerd Font
    ttf-proggyclean-nerd              # [fonts] ProggyClean Nerd Font
    ttf-recursive-nerd                # [fonts] Recursive Nerd Font
    ttf-roboto                        # [fonts] Android system font
    ttf-roboto-mono                   # [fonts] monospace variant font
    ttf-roboto-mono-nerd              # [fonts] Roboto Mono Nerd Font
    ttf-sarasa-gothic                 # [fonts] CJK+Latin coding font
    ttf-sazanami                      # [fonts] Japanese Gothic font
    ttf-scheherazade-new              # [fonts] Arabic script font
    ttf-sharetech-mono-nerd           # [fonts] ShareTech Mono Nerd Font
    ttf-sourcecodepro-nerd            # [fonts] Source Code Pro Nerd Font
    ttf-space-mono-nerd               # [fonts] Space Mono Nerd Font
    ttf-terminus-nerd                 # [fonts] Terminus Nerd Font
    ttf-tibetan-machine               # [fonts] Tibetan script font
    ttf-tinos-nerd                    # [fonts] Tinos Nerd Font
    ttf-ubuntu-font-family            # [fonts] Ubuntu system fonts
    ttf-ubuntu-mono-nerd              # [fonts] Ubuntu Mono Nerd Font
    ttf-ubuntu-nerd                   # [fonts] Ubuntu Nerd Font
    ttf-victor-mono-nerd              # [fonts] Victor Mono Nerd Font
    ttf-vlgothic                      # [fonts] Japanese Gothic font
    ttf-zed-mono-nerd                 # [fonts] Zed Mono Nerd Font

    ani-cli-git                       # [desktop] anime streaming CLI
    bemenu-wayland                    # [desktop] dmenu for wayland
    bleachbit                         # [desktop] disk space cleaner
    bluedevil                         # [desktop] plasma bluetooth applet
    bookokrat-bin                     # [desktop] terminal pdf
    brightnessctl                     # [desktop] backlight control
    chromium                          # [desktop] web browser
    cpio                              # [desktop] hyprpm extracts Hyprland headers with it
    cups-pk-helper                    # [desktop] cups polkit helper
    ddcutil                           # [desktop] DDC/CI monitor brightness control
    dolphin                           # [desktop] file manager (default; nemo kept alongside)
    feather-wallet                    # [desktop] monero wallet, wallets live in ~/sync/monero
    filezilla                         # [desktop] FTP client
    firefox                           # [desktop] web browser
    flat-remix-gtk                    # [desktop] GTK theme
    font-manager                      # [desktop] font management GUI
    gearlever                         # [desktop] AppImage manager
    geogebra-6-bin                    # [desktop] math/geometry app
    ghostty                           # [desktop] GPU terminal emulator
    gnome-calculator                  # [desktop] calculator app
    gnome-calendar                    # [desktop] calendar app
    gnome-maps                        # [desktop] maps application
    gnome-text-editor                 # [desktop] simple text editor
    gparted                           # [desktop] partition editor GUI
    grim                              # [desktop] wayland screenshot tool
    gtk3                              # [desktop] GTK3 toolkit
    gtk4                              # [desktop] GTK4 toolkit
    headsetcontrol                    # [desktop] headset control utility
    hollywood                         # [desktop] fake hacker terminal
    hyprcursor                        # [desktop] hyprland cursor format
    hypridle                          # [desktop] hyprland idle daemon
    hyprland                          # [desktop] wayland compositor
    hyprpicker                        # [desktop] wayland color picker
    hyprpm                            # [desktop] hyprland plugin manager
    jdownloader2                      # [desktop] download manager
    kdeconnect                        # [desktop] phone integration, firewall allows 1716
    kdeplasma-addons                  # [desktop] plasma weather and keyboard indicator applets
    kitty                             # [desktop] GPU terminal emulator
    konsole                           # [desktop] KDE terminal emulator
    krusader                          # [desktop] total commander
    kscreen                           # [desktop] plasma display configuration
    lib32-gtk3                        # [desktop] 32-bit GTK3
    libnotify                         # [desktop] desktop notification lib
    libreoffice-fresh                 # [desktop] office suite
    libx11                            # [desktop] X11 client library
    linecast                          # [desktop] tui weather
    localsend                         # [desktop] local file sharing
    logseq-desktop-bin                # [desktop] note-taking app
    ly                                # [desktop] TUI display manager
    lynx                              # [desktop] text-mode web browser
    metadata-cleaner                  # [desktop] strip file metadata
    minder                            # [desktop] mind mapping tool
    mission-center                    # [desktop] system monitor GUI
    mov-cli                           # [desktop] terminal movie streamer
    mpg123                            # [desktop] MP3 player CLI
    mpv                               # [desktop] media player
    nemo                              # [desktop] file manager
    nwg-look                          # [desktop] GTK theme configurator
    obsidian                          # [desktop] markdown notes app
    obsidian-icon-theme               # [desktop] Obsidian icon theme
    okular                            # [desktop] PDF/document viewer
    onlyoffice-bin                    # [desktop] office document suite
    pavucontrol                       # [desktop] PulseAudio volume GUI
    piper                             # [desktop] mouse config GUI
    plasma-desktop                    # [desktop] plasma fallback session, not the plasma group (drkonqi, discover, krdp, bigscreen)
    plasma-integration                # [desktop] Qt platform theme
    plasma-nm                         # [desktop] plasma network applet
    plasma-pa                         # [desktop] plasma volume applet
    plasma-vault                      # [desktop] plasma vault applet
    playerctl                         # [desktop] media player control
    polkit                            # [desktop] privilege authorization framework
    polkit-kde-agent                  # [desktop] KDE polkit agent
    print-manager                     # [desktop] plasma printer applet
    proton-authenticator-bin          # [desktop] Proton 2FA app
    proton-pass-bin                   # [desktop] Proton Pass password manager
    proton-vpn-qt-app                 # [desktop] ProtonVPN GUI client
    qbittorrent                       # [desktop] torrent client
    qt5-wayland                       # [desktop] Qt5 wayland platform
    qt6-wayland                       # [desktop] Qt6 wayland platform
    quickshell                        # [desktop] wayland status bar shell
    qutebrowser                       # [desktop] keyboard-driven web browser
    rose-pine-cursor                  # [desktop] cursor theme
    rose-pine-hyprcursor              # [desktop] hyprland cursor theme
    slurp                             # [desktop] wayland region selector
    snapshot                          # [desktop] GNOME camera app
    sowon-git                         # [desktop] tsoding timer
    stirling-pdf-bin                  # [desktop] PDF manipulation tool
    system-config-printer             # [desktop] printer config GUI
    tlpui                             # [desktop] TLP configuration GUI
    torbrowser-launcher               # [desktop] Tor Browser launcher
    uwsm                              # [desktop] universal wayland session manager
    waydroid                          # [desktop] Android container runtime
    wayland                           # [desktop] display server protocol
    wayland-boomer-git                # [desktop] wayland screen magnifier
    waypipe                           # [desktop] wayland network forwarding
    wev                               # [desktop] wayland event viewer
    wine-staging                      # [desktop] Windows compatibility layer
    wiremix                           # [desktop] pipewire mixer TUI
    wireplumber                       # [desktop] pipewire session manager
    wl-clipboard                      # [desktop] wayland clipboard tool
    wl_shimeji-git                    # [desktop] desktop mascot pet
    xclip                             # [desktop] X11 clipboard tool
    xdg-desktop-portal-gtk            # [desktop] GTK desktop portal
    xdg-desktop-portal-hyprland       # [desktop] hyprland desktop portal
    xdg-desktop-portal-kde            # [desktop] file chooser and settings portal, configs/xdg/hyprland-portals.conf
    xdg-user-dirs-gtk                 # [desktop] user dirs GTK integration
    xorg-server                       # [desktop] X11 display server
    xorg-xauth                        # [desktop] X11 auth utility
    xorg-xev                          # [desktop] X11 event viewer
    xorg-xeyes                        # [desktop] X11 demo eyes
    xorg-xhost                        # [desktop] X11 access control
    xorg-xinput                       # [desktop] X11 input config
    xorg-xwayland                     # [desktop] X11 on wayland
    ydotool                           # [desktop] generic input automation
    zathura                           # [desktop] minimal document viewer
    zathura-pdf-mupdf                 # [desktop] zathura PDF backend

    aseprite                          # [creating] pixel art editor
    audacity                          # [creating] audio editor
    blender                           # [creating] 3D modeling suite
    cava                              # [creating] audio visualizer
    converseen                        # [creating] batch image converter
    drawy                             # [creating] freehand drawing tool
    famistudio-bin                    # [creating] NES chiptune tracker
    feh                               # [creating] lightweight image viewer
    giflib                            # [creating] GIF image library
    gifsicle                          # [creating] GIF editing tool
    gimp                              # [creating] image editing suite
    gpu-screen-recorder               # [creating] low-overhead vaapi capture and replay buffer
    handbrake                         # [creating] video transcoder
    identity                          # [creating] media comparison
    inkscape                          # [creating] vector graphics editor
    kdenlive                          # [creating] video editor
    krita                             # [creating] digital painting app
    lib32-obs-vkcapture               # [creating] obs-vkcapture for 32-bit games
    lmms                              # [creating] music production software
    lorien-bin                        # [creating] infinite canvas drawing
    nsxiv                             # [creating] lightweight image viewer
    obs-audio-wave-bin                # [creating] OBS audio waveform plugin
    obs-pipewire-audio-capture        # [creating] OBS pipewire capture
    obs-plugin-waveform-bin           # [creating] OBS waveform plugin
    obs-studio                        # [creating] screen recording/streaming
    obs-studio-plugin-browser         # [creating] OBS browser source
    obs-vkcapture                     # [creating] OBS Vulkan/GL game capture, OBS_VKCAPTURE=1 or obs-gamecapture
    openscad                          # [creating] 3D CAD modeler
    pitivi                            # [creating] video editor
    python-websocket-client           # [creating] obs-websocket client for the bar's OBS widget
    qpwgraph                          # [creating] pipewire patchbay GUI
    rawtherapee                       # [creating] RAW photo editor
    sfxr-qt-bin                       # [creating] sound effect generator
    sox                               # [creating] audio processing tool
    tiled                             # [creating] tilemap editor
    xournalpp                         # [creating] handwritten note-taking

    biber                             # [latex] bibliography processor
    bibiman-bin                       # [latex] tui bibtext manager
    sioyek-git                        # [latex] pdf viewer for latex, synctex both ways (configs/sioyek)
    tectonic                          # [latex] LaTeX engine
    texlab                            # [latex] LaTeX language server
    texlive                           # [latex] LaTeX distribution
    texlive-lang                      # [latex] LaTeX language packs
    texmaker                          # [latex] LaTeX editor
    zotero-bin                        # [latex] reference manager

    chatuino-bin                      # [socials] tui twitch
    discord                           # [socials] chat/voice app
    discordo-git                      # [socials] terminal discord client
    element                           # [socials] matrix chat client
    hexchat                           # [socials] IRC client
    proton-mail-bin                   # [socials] Proton Mail client
    proton-meet-bin                   # [socials] Proton video calls
    signal-desktop                    # [socials] encrypted messaging app
    spicetify-cli                     # [socials] spotify theming CLI
    spotify                           # [socials] music streaming client
    spotify-player                    # [socials] terminal spotify client
    teamspeak3                        # [socials] voice chat client
    telegram-desktop                  # [socials] messaging app
    thunderbird                       # [socials] email client
    zapzap                            # [socials] WhatsApp desktop client

    curseforge                        # [gaming] mod manager launcher
    gamemode                          # [gaming] gaming performance daemon
    gamescope                         # [gaming] gaming compositor
    glslang                           # [gaming] GLSL/HLSL to SPIR-V compiler
    heroic-games-launcher-bin         # [gaming] epic/gog launcher
    kpat                              # [gaming] patience card games
    lib32-alsa-lib                    # [gaming] 32-bit ALSA lib
    lib32-alsa-plugins                # [gaming] 32-bit ALSA plugins
    lib32-gamemode                    # [gaming] gamemoderun for 32-bit games
    lib32-giflib                      # [gaming] 32-bit GIF lib
    lib32-gnutls                      # [gaming] 32-bit TLS lib
    lib32-libgcrypt                   # [gaming] 32-bit crypto lib
    lib32-libgpg-error                # [gaming] 32-bit gpg errors
    lib32-libjpeg-turbo               # [gaming] 32-bit JPEG lib
    lib32-libldap                     # [gaming] 32-bit LDAP lib
    lib32-libpng                      # [gaming] 32-bit PNG lib
    lib32-libpulse                    # [gaming] 32-bit PulseAudio
    lib32-libva                       # [gaming] 32-bit VAAPI lib
    lib32-libxcomposite               # [gaming] 32-bit X composite
    lib32-libxinerama                 # [gaming] 32-bit Xinerama lib
    lib32-mangohud                    # [gaming] mangohud for 32-bit games
    lib32-mesa                        # [gaming] 32-bit Mesa drivers
    lib32-mpg123                      # [gaming] 32-bit MP3 decoder
    lib32-ncurses                     # [gaming] 32-bit ncurses lib
    lib32-opencl-icd-loader           # [gaming] 32-bit OpenCL loader
    lib32-sqlite                      # [gaming] 32-bit SQLite lib
    lib32-vkbasalt                    # [gaming] vkbasalt for 32-bit games
    lib32-vulkan-icd-loader           # [gaming] 32-bit Vulkan loader
    lutris                            # [gaming] game launcher manager
    mangohud                          # [gaming] gaming performance overlay
    millennium                        # [gaming] Steam client theme loader
    minecraft-launcher                # [gaming] Minecraft game launcher
    modrinth-app                      # [gaming] minecraft mod manager
    nethack                           # [gaming] roguelike dungeon game
    opencomposite-git                 # [gaming] OpenXR to OpenVR
    path-of-building-community-git    # [gaming] PoE build planner
    proton-cachyos                    # [gaming] CachyOS Proton: vkd3d low-latency, reflex, ntsync
    protontricks                      # [gaming] Proton/Wine helper tool
    protonup-git                      # [gaming] Proton-GE installer
    r2modman-bin                      # [gaming] game mod manager
    rcon-cli                          # [gaming] game server RCON client
    shaderc                           # [gaming] shader compilation toolchain
    spirv-tools                       # [gaming] SPIR-V assembler/validator
    steam                             # [gaming] gaming platform client
    vkbasalt                          # [gaming] vulkan post-processing layer, opt-in per game
    vulkan-tools                      # [gaming] vulkaninfo/vkcube utilities
    vulkan-validation-layers          # [gaming] Vulkan validation layers
    wayvr-bin                         # [gaming] wayland VR desktop
    wivrn                             # [gaming] OpenXR streaming server for a wireless quest
    xivlauncher-bin                   # [gaming] FFXIV game launcher

    act                               # [programming] run CI locally
    afl++                             # [programming] fuzzing tool
    ali                               # [programming] tui webapp load testing
    android-ndk                       # [programming] Android native dev kit
    android-sdk                       # [programming] Android development kit
    apalache-bin                      # [programming] TLA+ symbolic model checker
    appimagetool-git                  # [programming] build AppImages
    asm-lsp                           # [programming] assembly language server (nvim lsp)
    ast-grep                          # [programming] code structural search
    avr-binutils                      # [programming] AVR assembler/linker
    avr-gcc                           # [programming] AVR C compiler
    avr-gdb                           # [programming] AVR debugger
    avr-libc                          # [programming] AVR C library
    aws-cli-v2                        # [programming] AWS command line
    bacon                             # [programming] rust background checker
    bat                               # [programming] cat with highlighting
    bc                                # [programming] calculator language
    bear                              # [programming] compile db generator
    bind                              # [programming] DNS utilities
    bloaty                            # [programming] binary size profiler
    bpftrace                          # [programming] eBPF tracing tool
    bugwarrior                        # [programming] bugtracker to taskwarrior
    bun-bin                           # [programming] fast javascript runtime
    cargo-afl                         # [programming] AFL fuzzing rust
    cargo-audit                       # [programming] rust vuln scanner
    cargo-bloat                       # [programming] rust binary size
    cargo-deny                        # [programming] rust dependency lint
    cargo-edit                        # [programming] rust cargo.toml editor
    cargo-expand                      # [programming] rust macro expansion
    cargo-flamegraph                  # [programming] rust profiler graphs
    cargo-fuzz                        # [programming] rust fuzzing tool
    cargo-generate                    # [programming] rust project templates
    cargo-info                        # [programming] crate info lookup
    cargo-leptos                      # [programming] leptos framework build
    cargo-llvm-cov                    # [programming] rust coverage tool
    cargo-make                        # [programming] rust task runner
    cargo-mutants                     # [programming] rust mutation testing
    cargo-nextest                     # [programming] faster rust test runner
    cargo-seek                        # [programming] crates.io search tool
    cargo-shear                       # [programming] unused deps detector
    cargo-show-asm                    # [programming] rust asm viewer
    cargo-shuttle                     # [programming] shuttle.rs deploy CLI
    cargo-sort-derives                # [programming] derive attribute sorter
    cargo-tarpaulin                   # [programming] rust code coverage
    cargo-update                      # [programming] update installed crates
    cargo-wizard                      # [programming] cargo profile helper
    cargo-zigbuild                    # [programming] cross-compile via zig
    cbmc                              # [programming] C/C++ bounded model checker
    cdecl                             # [programming] C declaration translator
    cgdb                              # [programming] curses gdb frontend
    chiko                             # [programming] gRPC TUI client
    clang                             # [programming] C/C++ compiler
    claude-code                       # [programming] Claude Code CLI
    cloc                              # [programming] count lines of code
    cmake                             # [programming] build system generator
    codelldb-bin                      # [programming] LLDB debugger extension
    contrast                          # [programming] WCAG contrast checker
    cppcheck                          # [programming] C/C++ static analysis
    crates-tui-git                    # [programming] crates.rs tui
    cross                             # [programming] rust cross-compilation
    csvi-bin                          # [programming] csv editor
    ctop                              # [programming] container resource monitor
    delve                             # [programming] go debugger (dap)
    deno                              # [programming] secure typescript runtime
    diesel-cli                        # [programming] rust ORM CLI
    difftastic                        # [programming] structural diff tool
    direnv                            # [programming] per-directory env loader
    dnsglobe                          # [programming] dns propagation viewer
    docker                            # [programming] container runtime
    docker-buildx                     # [programming] docker build extension
    docker-compose                    # [programming] multi-container orchestration
    dotnet-sdk                        # [programming] .NET SDK, mason builds csharpier with it
    ecgen                             # [programming] elliptic curve generator, mirror/pkgbuilds
    elan-lean                         # [programming] Lean toolchain manager
    emacs                             # [programming] text editor
    emscripten                        # [programming] C/C++ to wasm
    entr                              # [programming] run on file change
    expect                            # [programming] scripted terminal automation
    fasm                              # [programming] flat assembler
    figlet                            # [programming] ascii text banners
    flamegraph                        # [programming] perf stackcollapse + flamegraph scripts
    flamelens                         # [programming] tui flamegraph viewer
    flux-rs                           # [programming] rust refinement types, mirror/pkgbuilds
    ftxui                             # [programming] C++ terminal UI lib
    gap                               # [programming] computational group theory
    gcc                               # [programming] C/C++ compiler
    gcc-fortran                       # [programming] Fortran compiler
    gdb                               # [programming] GNU debugger
    gemini-cli                        # [programming] Google Gemini CLI
    genius                            # [programming] math calculator app
    gf2-git                           # [programming] debugger
    gh-dash                           # [programming] GitHub dashboard TUI
    gh-enhance-bin                    # [programming] gh-dash actions extension
    ghcup-hs-bin                      # [programming] Haskell toolchain installer
    git-absorb                        # [programming] absorbing submodules
    git-age                           # [programming] git age encryption
    git-delta                         # [programming] syntax-highlighting diff pager
    git-filter-repo                   # [programming] git history rewriter
    git-lfs                           # [programming] git large file storage
    github-cli                        # [programming] GitHub CLI (gh)
    github-copilot-cli                # [programming] Copilot CLI tool
    gitleaks                          # [programming] git secrets scanner
    glfw                              # [programming] OpenGL windowing lib
    glm                               # [programming] OpenGL math library
    glow                              # [programming] markdown terminal renderer
    gnucobol                          # [programming] cobol compiler
    gnuplot                           # [programming] plotting utility
    go                                # [programming] Go programming language
    go-yq                             # [programming] YAML processor CLI (mikefarah)
    godot                             # [programming] game engine
    gonzo                             # [programming] tui log analysis
    grafana-alloy                     # [programming] telemetry collector (promtail successor)
    graphviz                          # [programming] graph visualization tool
    grex                              # [programming] regex generator
    gup                               # [programming] go binary installer/updater
    heaptrack                         # [programming] heap memory profiler
    heh                               # [programming] byte editor
    helm                              # [programming] kubernetes package manager
    help2man                          # [programming] generate man pages
    herdr-bin                         # [programming] AI agent terminal manager
    hermes-agent                      # [programming] AI agent
    hotspot                           # [programming] Linux perf GUI
    hunspell-en_us                    # [programming] spell dictionary for emacs, shares nvim's word list
    hyperfine                         # [programming] command benchmarking tool
    irust                             # [programming] rust REPL shell
    jdk-openjdk                       # [programming] Java JDK (jdtls needs 21+)
    jetbrains-toolbox                 # [programming] JetBrains IDE manager
    jless                             # [programming] JSON viewer TUI
    jnv                               # [programming] interactive JSON navigator
    jrnl                              # [programming] command-line journal
    jujutsu                           # [programming] git-compatible VCS
    jupyterlab                        # [programming] notebook IDE
    k9s                               # [programming] kubernetes TUI
    kani-verifier                     # [programming] rust formal verifier
    kcachegrind                       # [programming] valgrind callgrind/cachegrind GUI
    kubecolor                         # [programming] kubectl colorized output
    kubectl                           # [programming] kubernetes CLI
    kubectx                           # [programming] kubernetes context switcher
    lazydocker                        # [programming] docker TUI
    lazygit                           # [programming] git TUI
    lazyjira-bin                      # [programming] jira tui
    lazyjj                            # [programming] jujutsu TUI
    lazymake-bin                      # [programming] makefile TUI
    lazysql                           # [programming] SQL database TUI
    lcov                              # [programming] code coverage reports
    lean-tui                          # [programming] Lean theorem prover TUI
    leptosfmt                         # [programming] leptos code formatter
    libvirt                           # [programming] libvirt
    libxslt                           # [programming] XSLT transform lib
    liquid-fixpoint                   # [programming] horn clause solver, mirror/pkgbuilds
    llvm                              # [programming] compiler infrastructure
    loki                              # [programming] log aggregation backend
    ls-horizons                       # [programming] deep space network tracker
    ltrace                            # [programming] library call tracer
    luarocks                          # [programming] Lua package manager
    make                              # [programming] build automation tool
    man-db                            # [programming] manual page database
    maven                             # [programming] Java build tool
    mdbook                            # [programming] markdown book generator
    mergiraf                          # [programming] merge conflict resolver
    mermaid-cli                       # [programming] diagram generator CLI
    meson                             # [programming] build system tool
    micro                             # [programming] terminal text editor
    miller                            # [programming] CSV/JSON data tool
    mingw-w64-gcc                     # [programming] Windows cross-compiler
    minikube                          # [programming] local kubernetes cluster
    mkcert                            # [programming] local TLS certificates
    mold                              # [programming] fast linker
    nano                              # [programming] terminal text editor
    nasm                              # [programming] x86 assembler
    neovide                           # [programming] neovim GUI frontend
    neovim                            # [programming] modal text editor
    ninja                             # [programming] fast build system
    nix                               # [programming] Nix package manager
    nnd                               # [programming] linux debugger
    nodejs                            # [programming] JavaScript runtime
    npm                               # [programming] node package manager
    odin                              # [programming] Odin programming language
    oha                               # [programming] HTTP load testing
    onefetch                          # [programming] git repo summary
    opam                              # [programming] OCaml package manager
    openapi-tui                       # [programming] openapi tui
    osmium-tool                       # [programming] OpenStreetMap data tool
    osslsigncode                      # [programming] authenticode signing tool
    osv-scanner                       # [programming] dependency vulnerability scanner
    pastel                            # [programming] color manipulation CLI
    phoronix-test-suite               # [programming] benchmarking suite
    pipeline-gtk                      # [programming] GStreamer pipeline debugger
    pkgconf                           # [programming] package compile flags
    postgresql                        # [programming] relational database
    postgresql-libs                   # [programming] postgres client libs
    posting                           # [programming] HTTP client TUI
    pre-commit                        # [programming] git hook manager
    prettier                          # [programming] code formatter
    protobuf                          # [programming] protocol buffers runtime
    py-spy                            # [programming] sampling profiler for python
    python-faker                      # [programming] fake data generator
    python-hypothesis                 # [programming] property-based testing
    python-ipykernel                  # [programming] Jupyter python kernel
    python-jsonschema                 # [programming] JSON schema validator
    python-jupytext                   # [programming] jupytext CLI: .ipynb <-> text
    python-matplotlib                 # [programming] Python plotting library
    python-numba                      # [programming] Python JIT compiler
    python-numpy                      # [programming] numerical computing library
    python-openapi-spec-validator     # [programming] OpenAPI spec validator
    python-pandas                     # [programming] data analysis library
    python-pillow                     # [programming] Python imaging library
    python-pip                        # [programming] Python package installer
    python-poetry                     # [programming] Python dependency manager
    python-pydantic                   # [programming] data validation library
    python-pygments                   # [programming] syntax highlighting library
    python-pynvim                     # [programming] nvim python provider
    python-scikit-learn               # [programming] machine learning library
    python-scipy                      # [programming] scientific computing library
    python-snakeviz                   # [programming] profiler visualization tool
    python-sympy                      # [programming] symbolic math library
    python-tree-sitter-html           # [programming] HTML parser bindings
    python-tree-sitter-javascript     # [programming] JS parser bindings
    python-tree-sitter-json           # [programming] JSON parser bindings
    qbe                               # [programming] compiler backend
    qmk                               # [programming] keyboard firmware framework
    quickjs                           # [programming] embeddable JS engine
    r                                 # [programming] R statistical language
    raddebugger-git                   # [programming] reverse debugger
    raylib                            # [programming] game programming library
    renderdoc                         # [programming] graphics frame debugger
    reptyr                            # [programming] reattach process to terminal
    resvg                             # [programming] SVG rendering library
    rgx                               # [programming] regex testing
    ripgrep                           # [programming] fast recursive grep
    rr                                # [programming] record-replay time-travel debugger
    rstudio-desktop-bin               # [programming] R development IDE
    rtk                               # [programming] tool compression
    ruff                              # [programming] fast python linter/formatter
    rustfilt                          # [programming] rust symbol demangler
    sagemath                          # [programming] computer algebra system
    samply                            # [programming] sampling profiler
    sccache                           # [programming] compiler cache tool
    sdl3                              # [programming] multimedia/game library
    serpl                             # [programming] search-replace TUI tool
    skaffold                          # [programming] kubernetes dev workflow
    slides-git                        # [programming] terminal presentation tool
    sops                              # [programming] secrets encryption tool
    speedscope                        # [programming] flamegraph profiler viewer
    sqlite                            # [programming] embedded SQL database
    sqlitebrowser                     # [programming] SQLite database GUI
    sqlx-cli                          # [programming] rust SQL migrations CLI
    stackit-cli                       # [programming] STACKIT cloud CLI
    strace                            # [programming] syscall tracer
    strace-tui                        # [programming] strace-tui
    taskwarrior-tui                   # [programming] taskwarrior terminal UI
    tauri-cli                         # [programming] tauri app CLI
    terraform                         # [programming] infrastructure as code
    tesseract                         # [programming] OCR engine
    tesseract-data-deu                # [programming] German OCR data
    tesseract-data-eng                # [programming] English OCR data
    tig                               # [programming] git repository browser
    timew                             # [programming] time tracking CLI
    tinymist-bin                      # [programming] typst language server
    tla-toolbox                       # [programming] TLA+ spec + TLC model checker
    tokei                             # [programming] code line counter
    tokui                             # [programming] code stats TUI
    topology-toolkit                  # [programming] scalar field analysis
    tracy                             # [programming] realtime frame profiler
    tree-sitter-cli                   # [programming] incremental parser generator
    trivy                             # [programming] container vulnerability scanner
    trufflehog                        # [programming] secrets scanning tool
    trunk                             # [programming] rust wasm tooling
    typos                             # [programming] source code spell checker (typos-lsp backend)
    typst                             # [programming] modern typesetting
    typstyle                          # [programming] typst formatter
    updo                              # [programming] website uptime monitor
    uv                                # [programming] fast Python package manager
    vale                              # [programming] prose linter
    valgrind                          # [programming] memory debugging/profiling tool
    vscodium-bin                      # [programming] VS Code de-branded
    wrk                               # [programming] HTTP benchmarking tool
    wscat                             # [programming] websocket CLI client
    xh                                # [programming] friendly HTTP client
    xplr                              # [programming] terminal file picker
    yozefu                            # [programming] kafka browser TUI
    z3                                # [programming] SMT theorem prover
    zed                               # [programming] collaborative code editor
    zig                               # [programming] Zig programming language
    zizmor                            # [programming] workflow auditing

    ollama-rocm                       # [rocm] ROCm/HIP GPU backend for ollama (official, gfx1101)
    python-pytorch-opt-rocm           # [rocm] ML framework (AMD, AVX2 optimized)

    llmfit                            # [llm] which LLMs fit this hardware (tui/cli)
    ollama                            # [llm] local LLM runner (daemon + CPU backend)

    distrobox                         # [qemu] containerized distro tool
    gnome-boxes                       # [qemu] VM manager GUI
    qemu-full                         # [qemu] machine emulator/virtualizer

    aircrack-ng                       # [pentesting] wifi security auditing
    amass-bin                         # [pentesting] attack-surface mapping and subdomain enum
    angryoxide                        # [pentesting] tui wifi pentesting
    arjun                             # [pentesting] HTTP param discovery
    armitage                          # [pentesting] metasploit GUI, mirror/pkgbuilds
    arp-scan                          # [pentesting] ARP network scanner
    bettercap                         # [pentesting] network attack framework
    binsider                          # [pentesting] binary analysis TUI
    binwalk                           # [pentesting] firmware image extraction
    bloodhound-cli                    # [pentesting] BloodHound CE in docker, up/down on demand, mirror/pkgbuilds
    bloodyad                          # [pentesting] active directory privilege escalation
    caido-desktop                     # [pentesting] web security testing, burp alternative
    certipy-ad                        # [pentesting] AD CS (ESC) enumeration and abuse
    checksec                          # [pentesting] binary hardening checker
    chisel-tunnel-bin                 # [pentesting] TCP/UDP tunnel over HTTP
    dalfox-bin                        # [pentesting] XSS scanning tool
    dnsx-bin                          # [pentesting] fast dns resolver, feeds the recon chain
    dsniff                            # [pentesting] network sniffing tools
    endlessh-git                      # [pentesting] SSH tarpit (decoy on 22)
    enola                             # [pentesting] search usernames
    exploitdb                         # [pentesting] exploit database mirror
    fcrackzip                         # [pentesting] zip password cracker
    feroxbuster-git                   # [pentesting] fast content discovery / dir brute force
    ffuf-bin                          # [pentesting] web fuzzing tool
    foremost                          # [pentesting] file carving tool
    gau                               # [pentesting] get-all-urls tool
    ghidra                            # [pentesting] reverse engineering suite
    gobuster                          # [pentesting] directory/DNS brute-forcer
    gowitness-bin                     # [pentesting] web screenshot tool
    hashcat                           # [pentesting] password cracking tool
    honggfuzz-git                     # [pentesting] security-oriented fuzzer
    hping                             # [pentesting] packet crafting tool
    httpx-bin                         # [pentesting] HTTP probing tool
    hydra                             # [pentesting] login brute-forcer
    hysteria                          # [pentesting] proxy/tunnel tool
    i2pd                              # [pentesting] I2P network daemon
    idspoof                           # [pentesting] identity spoofer, mirror/pkgbuilds
    impacket                          # [pentesting] windows network protocol toolkit
    john                              # [pentesting] password cracker
    katana-bin                        # [pentesting] web crawling tool
    kerbrute-bin                      # [pentesting] kerberos user and password spraying
    kismet                            # [pentesting] wireless network detector
    kiterunner-bin                    # [pentesting] API endpoint bruteforcer
    macchanger                        # [pentesting] MAC address randomizer
    masscan                           # [pentesting] mass IP port scanner
    mdk4                              # [pentesting] wifi attack toolkit
    metasploit                        # [pentesting] exploitation framework
    mitmproxy                         # [pentesting] HTTPS intercepting proxy
    naabu-bin                         # [pentesting] port scanning tool
    netexec                           # [pentesting] active directory/windows network pentesting
    netscanner                        # [pentesting] network scanning TUI
    nikto                             # [pentesting] web server scanner
    nmap                              # [pentesting] network mapper scanner
    nuclei-bin                        # [pentesting] template-based vulnerability scanner
    nuclei-templates                  # [pentesting] nuclei scan templates
    obfs4proxy                        # [pentesting] Tor traffic obfuscator
    proxychains-ng                    # [pentesting] proxy chaining (proxychains4)
    pwdsafety                         # [pentesting] pwd checking
    pwndbg                            # [pentesting] GDB exploit-dev plugin
    python-frida                      # [pentesting] dynamic instrumentation toolkit
    python-pwntools                   # [pentesting] exploit development library
    reaver-wps-fork-t6x-git           # [pentesting] WPS PIN cracker
    responder                         # [pentesting] llmnr/nbt-ns/mdns poisoner
    rizin                             # [pentesting] reverse-engineering framework
    rustscan                          # [pentesting] fast port scanner, feeds nmap
    rz-cutter                         # [pentesting] reverse engineering GUI
    seclists                          # [pentesting] security wordlists collection
    semgrep-bin                       # [pentesting] static analysis for source and CTF audit
    shadowsocks-git                   # [pentesting] SOCKS5 proxy tunnel
    skipfish                          # [pentesting] web app security scanner
    sliver-git                        # [pentesting] C2 framework
    slowhttptest                      # [pentesting] DoS testing tool
    sqlmap-git                        # [pentesting] SQL injection tool
    sslscan                           # [pentesting] TLS/SSL cipher scanner
    subfinder-bin                     # [pentesting] subdomain discovery tool
    tcpdump                           # [pentesting] packet capture CLI
    testssl.sh                        # [pentesting] TLS/SSL testing script
    theharvester                      # [pentesting] email and subdomain OSINT
    veil-bin                          # [pentesting] antivirus evasion framework
    volatility3-git                   # [pentesting] memory forensics framework
    wafw00f                           # [pentesting] WAF fingerprinting tool
    waybackurls                       # [pentesting] Wayback Machine URL fetcher
    wireshark-qt                      # [pentesting] network protocol analyzer
    yara                              # [pentesting] malware pattern matching
    zaproxy                           # [pentesting] OWASP ZAP scanner
)
FLATPAK_PKGS=(
    org.remmina.Remmina # [desktop] remote desktop client
    com.jeffser.Alpaca  # [llm] Ollama chat GUI
)

# attributes of NIXPKGS, pinned so a Generation installs what it was tested with; bump the rev by hand
NIXPKGS=github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4
NIX_PKGS=(
    devenv    # [programming] reproducible dev environments
    macaulay2 # [programming] commutative algebra/algebraic geometry, aur recipe is a 2019 snapshot on dropped mpir
    nixfmt    # [programming] nix formatter, nil_ls shells out to this
)

## PLATFORM

source ./scripts/lib/platform.sh
platform_load "$PWD"

filter_by_group() {
    awk -v arr="$1" -v groups="${PKG_GROUPS[*]}" '
        BEGIN { n = split(groups, g, " ") }
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
    ' "$PWD/install.sh"
}

mapfile -t PACKAGES < <(filter_by_group PACKAGES)
PACKAGES+=("${EXTRA_PACKAGES[@]}")
mapfile -t FLATPAK_PKGS < <(filter_by_group FLATPAK_PKGS)
mapfile -t NIX_PKGS < <(filter_by_group NIX_PKGS)

## LINK PACMAN CONFIG

# keyring first: pacman/link.sh's lsign needs it, a fresh bootstrap has it empty
sudo pacman-key --init
sudo pacman-key --populate archlinux

# first boot may get here before the network is up; stage.sh reruns install on the next boot, this spares it; wsl has no networkmanager
! command -v nm-online >/dev/null || nm-online -q --timeout=120 || echo "install: still offline after 120s" >&2

# without [lsck0] and its key every sync below would drift off the snapshot, so a failure aborts and stage.sh retries
pushd ./configs/pacman
(
    set -o pipefail
    bash ./link.sh 2>&1 | tee ./link.sh.log
) || {
    echo "configs/pacman/link.sh" >>"$FAILURES_FILE"
    exit "$EXIT_ABORTED"
}
popd

# a power cut mid-transaction leaves the lock behind, and every retry boot would fail on it
if [[ -e /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null; then sudo rm -f /var/lib/pacman/db.lck; fi

## INSTALLING ALL THE THINGS

source ./scripts/lib/sudo.sh
sudo_keepalive_start

## SOURCES

# [lsck0] (configs/pacman/pacman.conf) serves every listed package prebuilt; nothing is built here, gaps are only reported
targets=("${PACKAGES[@]}")

sudo pacman -Syy --noconfirm
# pacman reports every target it can not resolve, by name, provide or group, before it gives up
mapfile -t missing < <(pacman -Sp --noconfirm --print-format '%n' "${targets[@]}" 2>&1 >/dev/null \
    | sed -n 's/^error: target not found: //p')
declare -A MISSING=()
for pkg in "${missing[@]}"; do
    MISSING[$pkg]=1
    echo "not on the mirror: $pkg" >>"$FAILURES_FILE"
done
available=()
for pkg in "${targets[@]}"; do
    [[ -n "${MISSING[$pkg]:-}" ]] || available+=("$pkg")
done
echo "sources: ${#available[@]} packages in one pass, ${#missing[@]} not on the mirror" >&2

# the one download pass: -uu moves pacstrap's packages onto the snapshot, --ask 4 replaces the old lsck0-* names
sudo pacman -Suu --needed --noconfirm --ask 4 "${available[@]}"

## LEDGER

source ./scripts/lib/ledger.sh
# which lsck0 snapshot this machine runs: the pin, the db's publish time and its hash
lsck0_db=/var/lib/pacman/sync/lsck0.db
echo "${LSCK0_SNAPSHOT:-latest} $(date -ur "$lsck0_db" +%FT%TZ) $(sha256sum <"$lsck0_db" | cut -d' ' -f1)" | ledger_set snapshot
# after the install pass, so a dropped package only leaves once whatever replaced it is in
ledger_packages "${targets[@]}" || echo "ledger: removing dropped packages" >>"$FAILURES_FILE"

# stable only, a project pins nightly in its rust-toolchain.toml
if command -v rustup >/dev/null 2>&1; then
    rustup default stable || echo "rustup default stable" >>"$FAILURES_FILE"
fi

# user scope: a system deploy needs a polkit agent the unattended chain does not have
if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]] && command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        && flatpak install --user --noninteractive flathub "${FLATPAK_PKGS[@]}" \
        || echo "flatpak install --user ${FLATPAK_PKGS[*]}" >>"$FAILURES_FILE"
fi

if [[ ${#NIX_PKGS[@]} -gt 0 ]] && command -v nix >/dev/null 2>&1; then
    nix_cmd=(nix --extra-experimental-features 'nix-command flakes')
    sudo systemctl enable --now nix-daemon.socket || echo "nix-daemon.socket" >>"$FAILURES_FILE"
    # nix profile add stacks a duplicate on every rerun, so only the names the profile lacks
    mapfile -t nix_missing < <(comm -23 <(printf '%s\n' "${NIX_PKGS[@]}" | sort) \
        <("${nix_cmd[@]}" profile list --json | jq -r '.elements | keys[]' | sort))
    if ((${#nix_missing[@]})); then
        "${nix_cmd[@]}" profile add "${nix_missing[@]/#/$NIXPKGS#}" \
            || echo "nix profile add ${nix_missing[*]}" >>"$FAILURES_FILE"
    fi
fi

## SUMMARY

install_finished=1
if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED ==="
    cat "$FAILURES_FILE"
    exit "$EXIT_FAILURES"
fi
echo "All packages installed. Next: reboot, then ./config.sh"
rm -f "$FAILURES_FILE"
