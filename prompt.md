Remove the following packages from install.sh along with all configurations done to it:

opencode
gnome (KEEP ONLY GNOME BOXES), this might need to fix the keyring or portal?
4ed
doomemacs
cointop
ncdu
nushell
thefuck
flameshot
dust
pi-coding-agent-bin
rainfrog
kvirc
neochat
de.z_ray.Facetracker
wlogout
logradar

Once done reorder/sort the remaining packages into those groups, also check that the description is correct (max 4 words).

- base: bare arch system + security things + basic tooling like btop, zsh, ffmpeg, tmux, zip, rar, drivers, curl, kernels, mirrors, coreutils ... basically arch+
- fonts: fonts, font managers, font tools, nerd fonts, etc all except for the base fonts
- desktop: hyprland + plasma and a basic minimal desktop: browser, nemo, mpv, proton suite, onlyoffice, okular, printer, fonts, sound, gimp, plymuth, ly, torrent, tor ... basically a "normy" viable setup
- socials: zapzap, discord, spotify, telegram, obs, ...
- gaming: steam, vr, r2modman, heroic, lutris, protonup, modrith, ...
- creating: more advanced creativity tools: blender, krita, inkscape, video editors, cad, music stuff
- latex: as the name says, everything latex and bibtex etc.
- programming: editors, agents, language toolchains, debuggers, linters, zizmor, act, trufflehog, fuzzing, debugging tooling like dns checking, network scanning, most tui apps, docker, k8s, profiling / benchmarking tools...
- qemu: as the name says, everything needed for virtualization
- llm: everything needed to locally run llms, ollama, vllm, rocm stack, alpaca
- pentesting: ACTIVE scanning tools, metasploit, aircrack, pw braeaking tools, webapp scanners, anything that is NOT! normal programming tooling, reverse engineering, MITM, etc
- misc: anything that really doesnt fit anywhere else, this should be kept minimal

---

Address the following issues, keep track of your work through a TODO.md:

- mermaid live showcase in md are too big and also only show in insert mode?
- cleanup ./configs/qutebrowser/startpage.html
- spotify custom css hides the menu that lets you select the device to play on, as well as the queue
- make it so that the manual link scripts of hypr and shimeji run AUTOMATICALLY the first ever time hyprland is started, then never again.
- many keybinds in nvim dont have a which-key (like leader n)
- check if nvim debug and sql uis are setup correctly and work in a real project
- setup bookokrat with nvim for latex writing (like clicking in bookokrat should open the line in nvim). there also are rendering bugs with tmux. configure it with the colorscheme too.
- make sure herdr is nearly identical to tmux. also remove the popup that asks me for the name of a new tab.
- the theming of hms and tms is different. also using hms outside herdr doesnt attach to it.
- nvim lualine and tmux bar seem to not be styled correctly
- make sure install.sh sets ayu dark as default theme (that whole stack should be in base package group)
- there are recursive links in ./skills/ again
- can we have another REALLY dark theme and another brighter theme? ayu-light is literally WHITE lmao thats too bright
- have firefox, qutebrowser, zed, vscode have the same tab/window keybinds as nvim. so alt 1234 to switch, c to make x to close. can we have tiling too???
- ./scripts/alert.sh media-key, notification-send, watch-monitors, reminder, should be in quickshell
- all of the colorscheme stuff should be in config/wallust
- toggle shader should be in toggles
- we dont need all of that revert_package_side. JUST SELECT THE GROUPS and install them. nothing more. no uninstalling, no adding on later. group-select should just be part of install.sh
- there are two task-dashboards (one in scrips, one in skills)

---

make sure emacs is configured with the SAME keybindings as neovim and has the following features:

- window/pane/tab management like nvim
- file browser on the side through dired
- treesitter highlighting
- lsp along with the keybindings for it (goto definition, hover, references, etc), inline errors
- magit, gitsigns
- fuzzy finding like telescope
- compile mode
- terminal integration

---

Go look at quickshell, lets clean it up and make it nicer and more coherent, fix bugs and make it future proof.

Remember, this is the expected scope from quickshell:

- a nice and featurefull bar with widgets:
  - arch icon
  - workspaces
  - datetime (time + timezone, calendars, other timezones + timetravel, reminders, pomodoro) based on location
  - weather (current, forecast, alerts, radar) based on location
  - media controls + visualisation
  - system tray
  - system stats (cpu, ram, gpu, vram, disk, network, battery, power mode)
  - network (current network, connect to new network, tunnels, turn on/off network interfaces (lan, wifi, bluetooth, mobile, offline mode), internet speed)
  - volume control (input/output devices with volume, selecting default, mute, deafen toggles)
  - notifications (dnd, history, clear)
- wallpaper / theme selector
- app launcher like walker+elephant
- clipboard manager / history
- logout/exit screen

---

Check out ./skills/. Make sure:

- they are coherent, work together and dont contradict eachother
- they make sense
- they dont waste tokens
- are uptodate with current best practices

---

audit those dotfiles and the system it creates for security and performance.
