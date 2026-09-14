/**
 * @name QuickshellVoiceStatus
 * @author arch-dotfiles
 * @version 1.0.0
 * @description Publishes the current Discord voice-call state to a runtime JSON file for the quickshell bar widget (configs/quickshell/plugins/bar/widgets/Discord.qml).
 * @source https://github.com/luca/arch-dotfiles
 */

/*
 * WHY A BETTERDISCORD PLUGIN, AND NOT DISCORD RPC.
 *
 * The obvious route for "who is talking in my call" is Discord's local RPC
 * socket (`$XDG_RUNTIME_DIR/discord-ipc-0`), which exposes exactly the right
 * events: VOICE_STATE_UPDATE, SPEAKING_START, SPEAKING_STOP. Every one of them
 * is gated behind the `rpc` OAuth scope, and `rpc` is whitelist-only — you must
 * register an application on Discord's developer portal and authorise it, which
 * is a manual account-level step this repo cannot perform or check in.
 *
 * BetterDiscord is already installed here and already used for six other
 * plugins, and from inside the client the same state is a plain store read with
 * no account setup at all. So: read the stores, write a file, and let the shell
 * widget tail it.
 *
 * IT ALSO TAKES COMMANDS NOW, which the first version deliberately did not.
 * The bar widget needs to mute and deafen from the bar, and that cannot be done
 * by reading. The channel is as narrow as it can be: a single command file that
 * the plugin polls, whose only accepted verbs are listed in COMMANDS below, and
 * which is deleted the moment it is read. Nothing else outside Discord can
 * drive the client through this.
 *
 * Polled, not watched: Discord's renderer `fs` is a partial shim and
 * `fs.watchFile` is undefined in it (probed on this build), so there is no
 * watch to hang off. 250ms is imperceptible on a button press and is four
 * readFileSync calls a second against a file that almost never exists.
 *
 * THE FILE IS RUNTIME STATE, NOT CONFIG. It lives in XDG_RUNTIME_DIR (tmpfs,
 * cleared on logout) for the same reason toggles/lib.sh puts volatile state
 * there: a stale "you are in a call with three people" surviving a reboot is a
 * lie, and this one would be a lie rendered in the bar.
 */

/*
 * ONLY `fs`, AND ONLY LAZILY. Discord's renderer `require` resolves `fs` but
 * not every Node builtin, and BetterDiscord reports any throw during module
 * evaluation as "Could not be compiled" with no line number. So: no `path`, no
 * `os`, and `fs` resolved inside a try at start() rather than at module scope.
 */

module.exports = class QuickshellVoiceStatus {
  constructor() {
    this._stores = null;
    this._unsubscribes = [];
    this._heartbeat = null;
    this._lastPayload = "";
    this._fs = null;
    // NO /tmp FALLBACK. The first version fell back to /tmp when
    // XDG_RUNTIME_DIR was unset, which quietly downgraded both files from a
    // 0700 per-user tmpfs to a world-writable directory. The state file is
    // only a privacy leak there; the COMMAND file is worse, because anything
    // that can write it can mute and deafen the Discord client, and a
    // predictable path in /tmp is squattable by any local process.
    //
    // XDG_RUNTIME_DIR is always set under a systemd/logind session, which is
    // how this desktop starts. If it is missing, something is wrong enough
    // that publishing to a shared directory is not the right answer — the
    // plugin disables itself and the bar widget simply never appears.
    const runtimeDir = (typeof process !== "undefined" && process.env)
      ? process.env.XDG_RUNTIME_DIR : null;
    this._runtimeDir = runtimeDir || null;
    this._statePath = runtimeDir ? runtimeDir + "/quickshell-discord-voice.json" : null;
    this._commandPath = runtimeDir ? runtimeDir + "/quickshell-discord-cmd" : null;
    this._actions = null;
    this._commandPoll = null;
  }

  getName() { return "QuickshellVoiceStatus"; }
  getVersion() { return "1.0.0"; }
  getAuthor() { return "arch-dotfiles"; }
  getDescription() { return "Publishes voice-call state for the quickshell bar."; }

  // Stores are resolved by name through BdApi.Webpack.getStore, the one lookup
  // BetterDiscord commits to keeping working across Discord's own refactors.
  // Matching modules by shape or by minified property name is what makes this
  // kind of plugin break every few weeks.
  _resolveStores() {
    const get = (name) => {
      try { return BdApi.Webpack.getStore(name); } catch (e) { return null; }
    };
    return {
      voice: get("VoiceStateStore"),
      speaking: get("SpeakingStore"),
      users: get("UserStore"),
      media: get("MediaEngineStore"),
      selected: get("SelectedChannelStore"),
      channels: get("ChannelStore"),
      guilds: get("GuildStore"),
    };
  }

  // `userId` is always known; `user` may not be.
  //
  // UserStore only knows accounts the client has already loaded, so anyone in
  // the call you have never interacted with comes back null — and the first
  // version returned "" for exactly those people, which is a blank chip for
  // the participants you are least likely to recognise by name. The default
  // avatar is derived from the account id alone, so it is available even when
  // the user object is not.
  _avatarUrl(userId, user) {
    if (user && user.avatar) {
      const ext = String(user.avatar).startsWith("a_") ? "gif" : "png";
      return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=64`;
    }
    const id = String((user && user.id) || userId || "");
    if (!/^\d+$/.test(id)) return "";
    try {
      const index = Number((BigInt(id) >> 22n) % 6n);
      return `https://cdn.discordapp.com/embed/avatars/${index}.png`;
    } catch (e) {
      return "";
    }
  }

  _snapshot() {
    const s = this._stores;
    if (!s || !s.voice || !s.selected || !s.users) return { inVoice: false };

    const channelId = s.selected.getVoiceChannelId ? s.selected.getVoiceChannelId() : null;
    if (!channelId) return { inVoice: false };

    const states = s.voice.getVoiceStatesForChannel
      ? (s.voice.getVoiceStatesForChannel(channelId) || {}) : {};

    const ownId = s.users.getCurrentUser ? (s.users.getCurrentUser() || {}).id : null;

    const participants = [];
    for (const userId of Object.keys(states)) {
      const state = states[userId] || {};
      const user = s.users.getUser ? s.users.getUser(userId) : null;
      participants.push({
        id: String(userId),
        // A raw snowflake is not a name. Fall back to the nickname the voice
        // state itself carries before giving up and showing the id.
        name: String((user && (user.globalName || user.username))
                     || state.nick || state.username || userId),
        avatar: this._avatarUrl(userId, user),
        self: ownId != null && String(userId) === String(ownId),
        // Server mute and self mute are different states with different
        // remedies, so both are published rather than OR'd into "muted".
        mute: !!state.mute,
        selfMute: !!state.selfMute,
        deaf: !!state.deaf,
        selfDeaf: !!state.selfDeaf,
        video: !!state.selfVideo,
        streaming: !!state.selfStream,
        speaking: s.speaking && s.speaking.isSpeaking ? !!s.speaking.isSpeaking(userId) : false,
      });
    }

    // Own entry first, then everyone else alphabetically. Deliberately NOT
    // sorted by who is speaking: the widget renders them in order, and a list
    // that reshuffles on every speak event is unreadable.
    participants.sort((a, b) => {
      if (a.self !== b.self) return a.self ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    const channel = s.channels && s.channels.getChannel ? s.channels.getChannel(channelId) : null;
    const guild = channel && channel.guild_id && s.guilds && s.guilds.getGuild
      ? s.guilds.getGuild(channel.guild_id) : null;

    return {
      inVoice: true,
      // Timestamp so the widget can tell "quiet call" from "Discord died with
      // the file still on disk". Wall clock, because the reader is a different
      // process with no shared monotonic base.
      updatedAt: Date.now(),
      channel: channel ? String(channel.name || "") : "",
      guild: guild ? String(guild.name || "") : "",
      selfMute: s.media && s.media.isSelfMute ? !!s.media.isSelfMute() : false,
      selfDeaf: s.media && s.media.isSelfDeaf ? !!s.media.isSelfDeaf() : false,
      participants: participants,
    };
  }

  _write(payload) {
    if (!this._fs || !this._statePath) return;
    const text = JSON.stringify(payload);
    // The store change listeners fire far more often than the rendered state
    // actually changes — several times a second per participant during talk —
    // and most of those carry no difference the widget can see. Writing only
    // on a real change drops that to one write per visible transition. Speak
    // start/stop IS a visible transition, so an active call still writes a
    // couple of times a second; a quiet one writes only on the heartbeat.
    if (text === this._lastPayload) return;
    this._lastPayload = text;
    try {
      // Write-then-rename so the widget's FileView can never read a half-written
      // file. Quickshell's FileView re-arms its watch after an atomic write
      // (Util.rearmWatch), so this is the supported shape on the reading side.
      const tmp = this._statePath + ".tmp";
      this._fs.writeFileSync(tmp, text);
      this._fs.renameSync(tmp, this._statePath);
    } catch (e) {
      // A failed write must never surface in Discord's UI; the widget simply
      // keeps showing the last good state and then ages it out.
    }
  }

  // The only things the bar is allowed to ask Discord to do. Deliberately
  // short: mute and deafen are the two controls worth having on a bar, and
  // each is a single documented action on Discord's own media-engine module.
  _runCommand(cmd) {
    const actions = this._actions;
    if (!actions) return;
    switch (cmd) {
      case "toggleSelfMute":
        if (typeof actions.toggleSelfMute === "function") actions.toggleSelfMute();
        break;
      case "toggleSelfDeaf":
        if (typeof actions.toggleSelfDeaf === "function") actions.toggleSelfDeaf();
        break;
      default:
        return;
    }
    // Publish straight away rather than waiting for the store's own change
    // event, so the bar's toggle feels instant.
    this._lastPayload = "";
    this._publish();
  }

  _pollCommands() {
    if (!this._fs || !this._commandPath) return;
    let text;
    try {
      text = this._fs.readFileSync(this._commandPath, "utf8");
    } catch (e) {
      return;   // the normal case: no command pending
    }
    // Consumed before it is acted on, so a command that throws cannot be
    // replayed on every poll for the rest of the session.
    try { this._fs.unlinkSync(this._commandPath); } catch (e) {}
    for (const line of String(text).split("\n")) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        this._runCommand(JSON.parse(trimmed).cmd);
      } catch (e) {}
    }
  }

  _publish() {
    try {
      this._write(this._snapshot());
    } catch (e) {
      this._write({ inVoice: false });
    }
  }

  _subscribe(store) {
    if (!store || typeof store.addChangeListener !== "function") return;
    const handler = () => this._publish();
    store.addChangeListener(handler);
    this._unsubscribes.push(() => {
      try { store.removeChangeListener(handler); } catch (e) {}
    });
  }

  start() {
    // Same reasoning as the `fs` guard below: with nowhere safe to write, this
    // plugin has no way to reach the shell, so it does nothing at all rather
    // than subscribing to stores and polling for commands it cannot honour.
    if (!this._runtimeDir) return;

    try {
      this._fs = require("fs");
    } catch (e) {
      // No filesystem access: nothing this plugin does can reach the shell, so
      // do not subscribe to stores or arm a heartbeat for writes that cannot
      // happen.
      return;
    }

    this._stores = this._resolveStores();
    // The media-engine action module, found by a key it owns rather than by
    // shape: `toggleSelfMute` is stable across Discord's refactors in a way
    // that a minified property layout is not.
    try {
      this._actions = BdApi.Webpack.getByKeys("toggleSelfMute", "toggleSelfDeaf");
    } catch (e) {
      this._actions = null;
    }

    for (const key of ["voice", "speaking", "media", "selected"])
      this._subscribe(this._stores[key]);

    this._commandPoll = setInterval(() => this._pollCommands(), 250);

    // Heartbeat, not a poll: the change listeners carry every real update. This
    // exists so the file keeps a fresh timestamp during a long silent call, and
    // so the widget's staleness check does not hide a call nobody is talking in.
    this._heartbeat = setInterval(() => {
      if (this._stores && this._stores.selected
          && this._stores.selected.getVoiceChannelId
          && this._stores.selected.getVoiceChannelId()) {
        this._lastPayload = "";   // force a write so updatedAt advances
        this._publish();
      }
    }, 15000);

    this._publish();
  }

  stop() {
    for (const off of this._unsubscribes) off();
    this._unsubscribes = [];
    if (this._heartbeat) clearInterval(this._heartbeat);
    this._heartbeat = null;
    if (this._commandPoll) clearInterval(this._commandPoll);
    this._commandPoll = null;
    // Leave the widget in a definite state rather than letting it age out over
    // the next half minute.
    this._lastPayload = "";
    this._write({ inVoice: false });
  }
};
