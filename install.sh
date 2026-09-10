#!/usr/bin/env bash

set -e
exec > >(tee "install.log") 2>&1

FAILURES_FILE="$(pwd)/FAILURES"
: > "$FAILURES_FILE"

## PACKAGES
#   base        - core system/CLI tooling
#   desktop     - Hyprland/Wayland desktop environment
#   programming - languages, compilers, dev tooling
#   security    - pentesting/security auditing tools
#   creating    - audio/image/3D content creation
#   socials     - chat/voice/social apps
#   gaming      - games and gaming tooling
#   misc        - doesn't fit elsewhere

PACKAGES=(
    alsa-firmware # [base] ALSA sound firmware
    amdgpu_top # [base] AMD GPU monitor
    angryoxide # [security] tui wifi pentesting
    benben # [misc] terminal music player
    bluetui # [base] bluetooth tui
    bibiman-bin # [misc] tui bibtext manager
    bookokrat # [base] terminal pdf
    ali # [security] tui webapp load testing
    bpftop # [base] bpf monitor
    app2unit # [base] app to systemd unit
    chatuino # [socials] tui twitch
    cointop # [base] coin values
    csvi # [programming] csv editor
    diskwatch # [base] disk debugging
    dnsglobe # [programming] dns propagation viewer
    enola # [socials] search usernames
    flamelens # [programming] tui flamegraph viewer
    gonzo # [programming] tui log analysis
    harlequin # [programming] sql tui
    heh # [programming] byte editor
    gpg-tui # [base] gpg tui
    jolt # [base] battery debugging
    kmon # [base] kernel monitor
    lazyjira-bin # [programming] jira tui
    linecast # [misc] tui weather
    nnd # [programming] linux debugger
    openapi-tui # [programming] openapi tui
    crates-tui-git # [programming] crates.rs tui 
    base # [base] Arch base group
    bleachbit # [base] disk space cleaner
    blueberry # [base] bluetooth config GUI
    bluez # [base] bluetooth stack
    bluez-utils # [base] bluetooth utilities
    borg # [base] deduplicating backup tool
    btop # [base] resource monitor TUI
    btrfs-progs # [base] btrfs filesystem tools
    caligula # [base] disk imaging tool
    chafa # [base] terminal image renderer
    cifs-utils # [base] SMB/CIFS mount tools
    clonezilla # [base] disk cloning tool
    coreutils # [base] GNU core utilities
    cpufetch # [base] CPU info fetcher
    croc # [base] secure file transfer
    cronie # [base] cron daemon
    cups # [base] printing system
    cups-pdf # [base] print-to-PDF virtual printer
    curl # [base] HTTP client tool
    dog # [base] DNS lookup tool
    downgrade # [base] pacman package downgrader
    dua-cli # [base] disk usage analyzer
    dwarfs-bin # [base] compressed read-only fs
    dysk # [base] disk usage viewer
    efibootmgr # [base] EFI boot manager
    fastfetch # [base] system info fetcher
    file # [base] file type detector
    filezilla # [base] FTP client
    flatpak # [base] sandboxed app packages
    font-manager # [base] font management GUI
    ghostmirror # [base] mirrorlist ranking tool
    gnutls # [base] TLS library
    gparted # [base] partition editor GUI
    gping # [base] ping with graph
    identity # [base] identity management utility
    intel-media-driver # [base] Intel VAAPI driver
    ipython # [base] enhanced Python shell
    iwd # [base] iNet wireless daemon
    jdownloader2 # [base] download manager
    just # [base] command runner
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
    lib32-libxslt # [base] 32-bit XSLT lib
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
    localsend # [base] local file sharing
    lshw # [base] hardware lister
    lua51-luautf8 # [base] Lua UTF-8 lib
    man-pages # [base] Linux manual pages
    mesa # [base] graphics driver library
    metadata-cleaner # [base] strip file metadata
    mission-center # [base] system monitor GUI
    mov-cli # [base] terminal movie streamer
    mpg123 # [base] MP3 player CLI
    mpv # [base] media player
    mtools # [base] DOS filesystem tools
    mtr # [base] traceroute + ping
    ncdu # [base] disk usage analyzer
    ncurses # [base] terminal UI library
    neofetch # [base] system info display
    networkmanager # [base] network connection manager
    nss-mdns # [base] mDNS/.local name resolution (network printer discovery)
    noto-fonts # [base] Google Noto fonts
    noto-fonts-emoji # [base] Noto emoji fonts
    noto-fonts-extra # [base] Noto extra fonts
    ntfs-3g # [base] NTFS filesystem driver
    nushell # [base] structured data shell
    okular # [base] PDF/document viewer
    onlyoffice-bin # [base] office document suite
    openal # [base] 3D audio library
    openbsd-netcat # [base] netcat networking tool
    opencl-icd-loader # [base] OpenCL loader
    openssh # [base] SSH client/server
    openssl # [base] TLS/crypto toolkit
    ouch # [base] archive compression tool
    pacman-contrib # [base] pacman cache cleanup tools
    parallel # [base] run commands in parallel
    pdftk # [base] PDF toolkit
    pipewire # [base] audio/video server
    pipewire-alsa # [base] pipewire ALSA compat
    pipewire-pulse # [base] pipewire pulse compat
    plasma-integration # [base] Qt platform theme (QT_QPA_PLATFORMTHEME=kde reads kdeglobals)
    plymouth # [base] boot splash screen
    powerline-fonts # [base] powerline symbol fonts
    python-validity-git # [base] fingerprint reader driver
    qbittorrent # [base] torrent client
    ranger # [base] terminal file manager
    rar # [base] RAR archive tool
    rsync # [base] file sync tool
    rustnet # [base] network monitor TUI
    s-tui # [base] CPU stress/monitor TUI
    sane # [base] scanner access library
    smartmontools # [base] disk health monitoring
    socat # [base] socket relay tool
    sof-firmware # [base] sound open firmware
    sshfs # [base] SSH filesystem mount
    sshpass # [base] non-interactive SSH auth
    starship # [base] cross-shell prompt
    stirling-pdf-bin # [base] PDF manipulation tool
    sudo # [base] privilege escalation tool
    system-config-printer # [base] printer config GUI
    tar # [base] archiving utility
    tar-scripts # [base] tar helper scripts
    terminus-font-ttf # [base] bitmap terminal font
    thefuck # [base] command correction tool
    thermald # [base] thermal management daemon
    timeshift # [base] system backup/restore
    timew # [base] time tracking CLI
    tk # [base] Tcl/Tk GUI toolkit
    tldr # [base] simplified man pages
    tlp # [base] laptop power management
    tlpui # [base] TLP configuration GUI
    tmux # [base] terminal multiplexer
    tmux-fingers # [base] tmux copy-paste hints
    tparted-bin # [base] partitioning TUI tool
    traceroute # [base] network route tracer
    trash-cli # [base] CLI trash bin
    trippy # [base] traceroute + ping TUI
    ttf-anonymous-pro # [base] monospace font
    ttf-arphic-ukai # [base] Chinese kai font
    ttf-arphic-uming # [base] Chinese ming font
    ttf-atkinson-hyperlegible # [base] accessible reading font
    ttf-baekmuk # [base] Korean font family
    ttf-caladea # [base] Cambria-metric font
    ttf-cascadia-code # [base] monospace coding font
    ttf-cormorant # [base] serif display font
    ttf-crimson # [base] serif text font
    ttf-crimson-pro # [base] serif text font
    ttf-crimson-pro-variable # [base] variable serif font
    ttf-croscore # [base] Chrome OS fonts
    ttf-doulos-sil # [base] phonetic Unicode font
    ttf-droid # [base] Android system fonts
    ttf-eurof # [base] Eurostile-style font
    ttf-fantasque-sans-mono # [base] quirky monospace font
    ttf-fira-code # [base] ligature coding font
    ttf-fira-mono # [base] monospace font
    ttf-fira-sans # [base] humanist sans font
    ttf-gentium # [base] serif Unicode font
    ttf-gentium-book # [base] serif book font
    ttf-gentium-plus # [base] extended serif font
    ttf-hack # [base] monospace coding font
    ttf-hanazono # [base] Japanese CJK font
    ttf-hannom # [base] Vietnamese Han-Nom font
    ttf-ibm-plex # [base] IBM typeface family
    ttf-inconsolata # [base] monospace coding font
    ttf-indic-otf # [base] Indic script fonts
    ttf-input # [base] coding-focused font
    ttf-input-nerd # [base] Input font + icons
    ttf-jetbrains-mono # [base] monospace coding font
    ttf-jigmo # [base] rare CJK glyphs
    ttf-junicode # [base] medievalist Unicode font
    ttf-junicode-variable # [base] variable medievalist font
    ttf-khmer # [base] Khmer script font
    ttf-lato # [base] humanist sans font
    ttf-libertinus # [base] classic serif family
    ttf-linux-libertine # [base] free serif font
    ttf-linux-libertine-g # [base] Libertine with graphite
    ttf-material-icons # [base] material design icons
    ttf-material-symbols-variable # [base] variable material icons
    ttf-mona-sans # [base] GitHub display font
    ttf-monaspace-frozen # [base] GitHub monospace font
    ttf-monaspace-variable # [base] variable monospace font
    ttf-monofur # [base] futuristic monospace font
    ttf-monoid # [base] coding-focused monospace
    ttf-montserrat # [base] geometric sans font
    ttf-ms-fonts # [base] Microsoft core fonts
    ttf-nunito # [base] rounded sans font
    ttf-opensans # [base] humanist sans font
    ttf-overpass # [base] highway-gothic sans font
    ttf-roboto # [base] Android system font
    ttf-roboto-mono # [base] monospace variant font
    ttf-sarasa-gothic # [base] CJK+Latin coding font
    ttf-sazanami # [base] Japanese Gothic font
    ttf-scheherazade-new # [base] Arabic script font
    ttf-tibetan-machine # [base] Tibetan script font
    ttf-ubuntu-font-family # [base] Ubuntu system fonts
    ttf-vlgothic # [base] Japanese Gothic font
    unzip # [base] zip extraction tool
    update-grub # [base] GRUB config regenerator
    v4l-utils # [base] video4linux utilities
    v4l2loopback-dkms # [base] virtual video device
    v4l2loopback-utils # [base] v4l2loopback helper tools
    ventoy-bin # [base] multi-boot USB creator
    vulkan-icd-loader # [base] Vulkan loader library
    vulkan-intel # [base] Intel Vulkan driver
    vulkan-nouveau # [base] Nvidia open Vulkan
    vulkan-radeon # [base] AMD Vulkan driver
    waydroid # [base] Android container runtime
    wget # [base] file download utility
    whois # [base] domain lookup tool
    wireless_tools # [base] legacy wireless config
    wpa_supplicant # [base] wifi authentication daemon
    xdg-ninja # [base] XDG compliance checker
    xdg-user-dirs # [base] standard user directories
    xdg-utils # [base] desktop integration utilities
    xf86-video-ati # [base] legacy AMD driver
    xf86-video-nouveau # [base] open Nvidia driver
    yay # [base] AUR helper
    yt-dlp # [base] video downloader
    zathura # [base] minimal document viewer
    zathura-pdf-mupdf # [base] zathura PDF backend
    zip # [base] zip archiving tool
    zoxide # [base] smarter cd command
    zram-generator # [base] compressed swap generator
    zsh # [base] Z shell
    ani-cli-git # [desktop] anime streaming CLI
    bemenu-wayland # [desktop] dmenu for wayland
    brightnessctl # [desktop] backlight control
    chromium # [desktop] web browser
    cups-pk-helper # [desktop] cups polkit helper
    firefox # [desktop] web browser
    flameshot # [desktop] screenshot tool
    flat-remix-gtk # [desktop] GTK theme
    gamescope # [desktop] gaming compositor
    gearlever # [desktop] AppImage manager
    ghostty # [desktop] GPU terminal emulator
    gnome # [desktop] desktop environment
    gnome-boxes # [desktop] VM manager GUI
    gnome-calculator # [desktop] calculator app
    gnome-calendar # [desktop] calendar app
    gnome-maps # [desktop] maps application
    gnome-text-editor # [desktop] simple text editor
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
    kitty # [desktop] GPU terminal emulator
    lib32-gtk3 # [desktop] 32-bit GTK3
    libnotify # [desktop] desktop notification lib
    libx11 # [desktop] X11 client library
    ly # [desktop] TUI display manager
    lynx # [desktop] text-mode web browser
    nemo # [desktop] file manager
    nwg-look # [desktop] GTK theme configurator
    obsidian-icon-theme # [desktop] Obsidian icon theme
    pavucontrol # [desktop] PulseAudio volume GUI
    piper # [desktop] mouse config GUI
    plasma # [desktop] KDE desktop environment
    playerctl # [desktop] media player control
    polkit # [desktop] privilege authorization framework
    polkit-kde-agent # [desktop] KDE polkit agent
    python-pywalfox # [desktop] pywal firefox theming
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
    themix-gui-git # [desktop] GTK theme generator
    themix-plugin-base16-git # [desktop] themix base16 plugin
    uwsm # [desktop] universal wayland session manager
    wallust-git # [desktop] wallpaper colour extraction, replaced pywal
    wayland # [desktop] display server protocol
    wayland-boomer-git # [desktop] wayland screen magnifier
    waypipe # [desktop] wayland network forwarding
    wayvr-bin # [desktop] wayland VR desktop
    wev # [desktop] wayland event viewer
    wiremix # [desktop] pipewire mixer TUI
    wireplumber # [desktop] pipewire session manager
    wl-clipboard # [desktop] wayland clipboard tool
    wl_shimeji-git # [desktop] desktop mascot pet
    wlogout # [desktop] wayland logout menu
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
    act # [programming] run CI locally
    android-ndk # [programming] Android native dev kit
    android-sdk # [programming] Android development kit
    appimagetool-git # [programming] build AppImages
    ast-grep # [programming] code structural search
    aws-cli-v2 # [programming] AWS command line
    bacon # [programming] rust background checker
    base-devel # [programming] Arch build tools
    bat # [programming] cat with highlighting
    bc # [programming] calculator language
    bear # [programming] compile db generator
    biber # [programming] bibliography processor
    bind # [programming] DNS utilities
    bloaty # [programming] binary size profiler
    bugwarrior # [programming] bugtracker to taskwarrior
    cargo-bloat # [programming] rust binary size
    cargo-deny # [programming] rust dependency lint
    cargo-edit # [programming] rust cargo.toml editor
    cargo-expand # [programming] rust macro expansion
    cargo-flamegraph # [programming] rust profiler graphs
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
    cross # [programming] rust cross-compilation
    ctop # [programming] container resource monitor
    diesel-cli # [programming] rust ORM CLI
    difftastic # [programming] structural diff tool
    direnv # [programming] per-directory env loader
    distrobox # [programming] containerized distro tool
    docker # [programming] container runtime
    docker-buildx # [programming] docker build extension
    docker-compose # [programming] multi-container orchestration
    dust # [programming] du alternative TUI
    ecgen-git # [programming] elliptic curve generator
    elan-lean # [programming] Lean toolchain manager
    emacs # [programming] text editor
    emscripten # [programming] C/C++ to wasm
    entr # [programming] run on file change
    expect # [programming] scripted terminal automation
    eza # [programming] modern ls replacement
    fasm # [programming] flat assembler
    fd # [programming] find alternative
    ftxui # [programming] C++ terminal UI lib
    fzf # [programming] fuzzy finder
    gcc # [programming] C/C++ compiler
    gcc-fortran # [programming] Fortran compiler
    gdb # [programming] GNU debugger
    gemini-cli # [programming] Google Gemini CLI
    genius # [programming] math calculator app
    geogebra-6-bin # [programming] math/geometry app
    gf2-git # [programming] grep pattern wrapper
    gh-dash # [programming] GitHub dashboard TUI
    ghcup-hs-bin # [programming] Haskell toolchain installer
    git # [programming] version control
    git-delta # [programming] syntax-highlighting diff pager
    git-filter-repo # [programming] git history rewriter
    git-lfs # [programming] git large file storage
    github-cli # [programming] GitHub CLI (gh)
    github-copilot-cli # [programming] Copilot CLI tool
    glfw # [programming] OpenGL windowing lib
    glm # [programming] OpenGL math library
    glow # [programming] markdown terminal renderer
    gnuplot # [programming] plotting utility
    go # [programming] Go programming language
    graphviz # [programming] graph visualization tool
    grex # [programming] regex generator
    gup # [programming] go binary installer/updater
    heaptrack # [programming] heap memory profiler
    helm # [programming] kubernetes package manager
    help2man # [programming] generate man pages
    herdr-bin # [programming] AI agent terminal manager
    hermes-agent # [programming] AI agent
    hexyl # [programming] hex viewer CLI
    hotspot # [programming] Linux perf GUI
    hyperfine # [programming] command benchmarking tool
    jetbrains-toolbox # [programming] JetBrains IDE manager
    jless # [programming] JSON viewer TUI
    jnv # [programming] interactive JSON navigator
    jq # [programming] JSON processor CLI
    jujutsu # [programming] git-compatible VCS
    jupyterlab # [programming] notebook IDE
    k9s # [programming] kubernetes TUI
    kubecolor # [programming] kubectl colorized output
    kubectl # [programming] kubernetes CLI
    kubectx # [programming] kubernetes context switcher
    lazydocker-bin # [programming] docker TUI
    lazygit # [programming] git TUI
    lazyjj # [programming] jujutsu TUI
    lazymake # [programming] makefile TUI
    lazysql # [programming] SQL database TUI
    lcov # [programming] code coverage reports
    libxslt # [programming] XSLT transform lib
    llvm # [programming] compiler infrastructure
    logseq-desktop-bin # [programming] note-taking app
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
    nodejs # [programming] JavaScript runtime
    npm # [programming] node package manager
    obsidian # [programming] markdown notes app
    odin # [programming] Odin programming language
    oh-my-zsh-git # [programming] zsh config framework
    oha # [programming] HTTP load testing
    ollama-for-amd-git # [programming] local LLM runner (AMD)
    onefetch # [programming] git repo summary
    opam # [programming] OCaml package manager
    opencode # [programming] AI coding CLI
    opencomposite-git # [programming] OpenXR to OpenVR
    pandoc-cli # [programming] document format converter
    pastel # [programming] color manipulation CLI
    phoronix-test-suite # [programming] benchmarking suite
    pi-coding-agent-bin # [programming] AI coding agent
    pipeline-gtk # [programming] GStreamer pipeline debugger
    pkgconf # [programming] package compile flags
    postgresql # [programming] relational database
    postgresql-libs # [programming] postgres client libs
    posting # [programming] HTTP client TUI
    pre-commit # [programming] git hook manager
    prettier # [programming] code formatter
    procs # [programming] modern ps replacement
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
    python-pytorch-rocm # [programming] ML framework (AMD)
    python-scikit-learn # [programming] machine learning library
    python-scipy # [programming] scientific computing library
    python-snakeviz # [programming] profiler visualization tool
    python-sympy # [programming] symbolic math library
    qbe # [programming] compiler backend
    qemu-full # [programming] machine emulator/virtualizer
    quickjs # [programming] embeddable JS engine
    r # [programming] R statistical language
    rainfrog # [programming] postgres TUI client
    raylib # [programming] game programming library
    rclone # [programming] cloud storage sync
    renderdoc # [programming] graphics frame debugger
    reptyr # [programming] reattach process to terminal
    ripgrep # [programming] fast recursive grep
    rstudio-desktop-bin # [programming] R development IDE
    samply # [programming] sampling profiler
    sccache # [programming] compiler cache tool
    sd # [programming] sed alternative CLI
    sdl3 # [programming] multimedia/game library
    serpl # [programming] search-replace TUI tool
    skaffold # [programming] kubernetes dev workflow
    slides-git # [programming] terminal presentation tool
    speedscope # [programming] flamegraph profiler viewer
    sqlite # [programming] embedded SQL database
    sqlitebrowser # [programming] SQLite database GUI
    sqlx-cli # [programming] rust SQL migrations CLI
    tectonic # [programming] LaTeX engine
    terraform # [programming] infrastructure as code
    tesseract # [programming] OCR engine
    tesseract-data-deu # [programming] German OCR data
    tesseract-data-eng # [programming] English OCR data
    texlive # [programming] LaTeX distribution
    texlive-lang # [programming] LaTeX language packs
    texmaker # [programming] LaTeX editor
    tig # [programming] git repository browser
    tokei # [programming] code line counter
    topology-toolkit # [programming] scalar field analysis
    tree-sitter-cli # [programming] incremental parser generator
    ttf-monocraft-git # [programming] Minecraft-style monospace
    updo # [programming] website uptime monitor
    usage # [programming] CLI docs generator
    uv # [programming] fast Python package manager
    vim # [programming] modal text editor
    virt-manager # [programming] VM management GUI
    vscodium-bin # [programming] VS Code de-branded
    wrk # [programming] HTTP benchmarking tool
    wscat # [programming] websocket CLI client
    xh # [programming] friendly HTTP client
    yozefu # [programming] kafka browser TUI
    zed # [programming] collaborative code editor
    zig # [programming] Zig programming language
    afl++ # [security] fuzzing tool
    age # [security] file encryption tool
    aircrack-ng # [security] wifi security auditing
    argon2 # [security] password hashing tool
    arjun # [security] HTTP param discovery
    arp-scan # [security] ARP network scanner
    bettercap # [security] network attack framework
    binsider # [security] binary analysis TUI
    bpftrace # [security] eBPF tracing tool
    burpsuite # [security] web security testing
    cargo-audit # [security] rust vuln scanner
    cargo-fuzz # [security] rust fuzzing tool
    dalfox-bin # [security] XSS scanning tool
    dsniff # [security] network sniffing tools
    exploitdb # [security] exploit database mirror
    fail2ban # [security] intrusion prevention tool
    fcrackzip # [security] zip password cracker
    ffuf-bin # [security] web fuzzing tool
    foremost # [security] file carving tool
    gau # [security] get-all-urls tool
    ghidra # [security] reverse engineering suite
    gitleaks # [security] git secrets scanner
    gobuster # [security] directory/DNS brute-forcer
    gowitness-bin # [security] web screenshot tool
    gufw # [security] firewall GUI (ufw)
    hashcat # [security] password cracking tool
    hping # [security] packet crafting tool
    httpx-bin # [security] HTTP probing tool
    hydra # [security] login brute-forcer
    hysteria # [security] proxy/tunnel tool
    i2pd # [security] I2P network daemon
    john # [security] password cracker
    katana-bin # [security] web crawling tool
    kismet # [security] wireless network detector
    kiterunner-bin # [security] API endpoint bruteforcer
    lynis # [security] security auditing tool
    mdk4 # [security] wifi attack toolkit
    metasploit # [security] exploitation framework
    mitmproxy # [security] HTTPS intercepting proxy
    mkcert # [security] local TLS certificates
    naabu-bin # [security] port scanning tool
    netscanner # [security] network scanning TUI
    nftables # [security] firewall packet filter
    nikto # [security] web server scanner
    nmap # [security] network mapper scanner
    nuclei-bin # [security] vulnerability scanner
    nuclei-templates # [security] nuclei scan templates
    obfs4proxy # [security] Tor traffic obfuscator
    openvpn # [security] VPN client/server
    ossec-hids-local # [security] host intrusion detection
    osslsigncode # [security] authenticode signing tool
    pass # [security] CLI password manager
    portmaster-bin # [security] application firewall
    proton-authenticator-bin # [security] Proton 2FA app
    proton-vpn-qt-app # [security] ProtonVPN GUI client
    pwndbg # [security] GDB exploit-dev plugin
    python-pwntools # [security] exploit development library
    reaver-wps-fork-t6x-git # [security] WPS PIN cracker
    rkhunter # [security] rootkit detection tool
    rz-cutter # [security] reverse engineering GUI
    seclists # [security] security wordlists collection
    skipfish # [security] web app security scanner
    slowhttptest # [security] DoS testing tool
    sops # [security] secrets encryption tool
    sqlmap-git # [security] SQL injection tool
    sslscan # [security] TLS/SSL cipher scanner
    subfinder-bin # [security] subdomain discovery tool
    testssl.sh # [security] TLS/SSL testing script
    tor-router # [security] transparent tor routing
    torbrowser-launcher # [security] Tor Browser launcher
    trivy # [security] container vulnerability scanner
    trufflehog # [security] secrets scanning tool
    valgrind # [security] memory debugging tool
    veil-bin # [security] antivirus evasion framework
    veracrypt # [security] disk encryption tool
    volatility3-git # [security] memory forensics framework
    wafw00f # [security] WAF fingerprinting tool
    wireguard-tools # [security] WireGuard VPN tools
    wireguard-ui-bin # [security] WireGuard web UI
    wireshark-qt # [security] network protocol analyzer
    z3 # [security] SMT theorem prover
    zaproxy # [security] OWASP ZAP scanner
    aseprite # [creating] pixel art editor
    audacity # [creating] audio editor
    blender # [creating] 3D modeling suite
    cava # [creating] audio visualizer
    converseen # [creating] batch image converter
    drawy # [creating] freehand drawing tool
    easyeffects # [creating] audio effects processor
    famistudio-bin # [creating] NES chiptune tracker
    feh # [creating] lightweight image viewer
    ffmpeg # [creating] audio/video converter
    giflib # [creating] GIF image library
    gifsicle # [creating] GIF editing tool
    gimp # [creating] image editing suite
    glava # [creating] audio visualizer
    handbrake # [creating] video transcoder
    imagemagick # [creating] image manipulation CLI
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
    openscad # [creating] 3D CAD modeler
    opentabletdriver-git # [creating] graphics tablet driver
    pitivi # [creating] video editor
    qpwgraph # [creating] pipewire patchbay GUI
    rawtherapee # [creating] RAW photo editor
    sfxr-qt-bin # [creating] sound effect generator
    sox # [creating] audio processing tool
    tiled # [creating] tilemap editor
    xournalpp # [creating] handwritten note-taking
    betterdiscord-installer # [socials] BetterDiscord installer
    betterdiscordctl-git # [socials] BetterDiscord CLI installer
    discord # [socials] chat/voice app
    discordo-git # [socials] terminal discord client
    element # [socials] matrix chat client
    hexchat # [socials] IRC client
    kvirc # [socials] IRC client
    neochat # [socials] matrix chat client
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
    godot # [gaming] game engine
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
    wine-staging # [gaming] Windows compatibility layer
    xivlauncher-bin # [gaming] FFXIV game launcher
    cmatrix # [misc] matrix terminal animation
    cowsay # [misc] ascii cow sayings
    figlet # [misc] ascii text banners
    focus-bin # [misc] focus/pomodoro timer
    hollywood # [misc] fake hacker terminal
    jrnl # [misc] command-line journal
    khal # [misc] CLI calendar tool
    lolcat # [misc] rainbow text output
    minder # [misc] mind mapping tool
    osmium-tool # [misc] OpenStreetMap data tool
    qmk # [misc] keyboard firmware framework
    rgx # [programming] regex testing
    strace-tui # [programming] strace-tui
    superseedr # [misc] terminal torrent
    usbtree # [base] usb tui
    zizmor # [security] workflow auditing
    sowon-git # [misc] pomodoro timer TUI
    taskwarrior-tui # [misc] taskwarrior terminal UI
    pomo # [misc] terminal pomodoro
    posting # [programming] terminal http client
    pwdsafety # [security] pwd checking
    pwndbg # [security] reverse engineering
    tty-clock # [misc] terminal clock display
    wiki-tui # [misc] Wikipedia terminal browser
    rtk # [programming] tool compression
)

FLATPAK_PKGS=(
    com.jeffser.Alpaca # [programming] Ollama chat GUI
    de.z_ray.Facetracker # [creating] webcam face tracking
)

CARGO_PKGS=(
    tmux-sessionizer # [base] tmux project sessionizer
    bootimage # [programming] bootable kernel images
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
    Raijin # [programming] rust weather TUI
    rustfilt # [programming] rust symbol demangler
    tauri-cli # [programming] tauri app CLI
    cargo-afl # [security] AFL fuzzing rust
)

CARGO_PKGS_GIT=(
    https://github.com/nanook72/logradar # [programming] log pattern analysis TUI
)

GO_PKGS=(
    github.com/felangga/chiko/cmd/chiko@latest # [programming] gRPC TUI client
    github.com/zdyxry/tokui@latest # [programming] code stats TUI
    github.com/litescript/ls-horizons/cmd/ls-horizons@latest # [misc] deep space network tracker
)

NIX_PKGS=(
    nixpkgs#devenv # [programming] reproducible dev environments
)

## PACKAGE GROUPS

# Ask once which of the 8 package groups to enable (default: all of them —
# see scripts/groups-select.sh) unless a previous run already chose. To
# change the selection later, rerun scripts/groups-select.sh directly, then
# scripts/groups-apply.sh install|remove <group> to act on the change —
# this install.sh pass only ever asks/filters once, up front.
GROUPS_STATE="$HOME/.config/arch-dotfiles/groups.conf"
[[ -f "$GROUPS_STATE" ]] || "$(pwd)/scripts/groups-select.sh"
ENABLED_GROUPS=$(cat "$GROUPS_STATE")

# Every entry in PACKAGES/FLATPAK_PKGS/CARGO_PKGS/CARGO_PKGS_GIT/GO_PKGS is
# commented `# [group] description` — comments never survive into a bash
# array at runtime, so this re-parses this file's own source per array name
# (plain substring match on "[groupname]", not a regex: an unescaped `[` in
# a dynamic awk regex opens a bracket expression instead of matching a
# literal bracket, verified the hard way before landing this).
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

## REMOVE PASSWORD FROM SUDO

if ! sudo grep -q '$USER' /etc/sudoers; then
    echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers
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
rustup toolchain install nightly
rustup toolchain install stable
rustup default stable

# install all the things
[[ ${#PACKAGES[@]} -eq 0 ]] || yay -S "${PACKAGES[@]}" --noconfirm --mflags --skipinteg
sudo pacman -S $(pacman -Sgq nerd-fonts) --noconfirm
[[ ${#CARGO_PKGS[@]} -eq 0 ]] || cargo install --locked "${CARGO_PKGS[@]}" -j $(nproc)
for git_pkg in "${CARGO_PKGS_GIT[@]}"; do
    cargo install --git "$git_pkg" -j $(nproc)
done
[[ ${#GO_PKGS[@]} -eq 0 ]] || go install "${GO_PKGS[@]}"
[[ ${#FLATPAK_PKGS[@]} -eq 0 ]] || flatpak install flathub -y "${FLATPAK_PKGS[@]}"
[[ ${#NIX_PKGS[@]} -eq 0 ]] || nix profile install --extra-experimental-features 'nix-command flakes' "${NIX_PKGS[@]}"

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

./scripts/switch-wallpaper.sh ./wallpapers/gargantua.jpg >/dev/null 2>/dev/null

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

nvim &
