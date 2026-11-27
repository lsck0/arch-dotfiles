import qs.Commons

// Fluxer's voice call, as Discord.qml shows Discord's: socials/fluxer's fluxer-voice.nu writes the same state over its
// DevTools port; no mute or leave buttons, Fluxer takes no commands from the shell
Discord {
  moduleName: "fluxer"
  statePath: Paths.runtimeDir + "/quickshell-fluxer-voice.json"
  controllable: false
}
