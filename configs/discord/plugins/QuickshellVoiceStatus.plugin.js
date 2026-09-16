/**
 * @name QuickshellVoiceStatus
 * @author Luca
 * @version 1.0.0
 * @description Publish current VC to quickshell.
 * @source https://github.com/luca/arch-dotfiles
 */

module.exports = class QuickshellVoiceStatus {
  constructor() {
    this._stores = null;
    this._unsubscribes = [];
    this._heartbeat = null;
    this._lastPayload = "";
    this._fs = null;
    const runtimeDir =
      typeof process !== "undefined" && process.env
        ? process.env.XDG_RUNTIME_DIR
        : null;
    this._runtimeDir = runtimeDir || null;
    this._statePath = runtimeDir
      ? runtimeDir + "/quickshell-discord-voice.json"
      : null;
    this._commandPath = runtimeDir
      ? runtimeDir + "/quickshell-discord-cmd"
      : null;
    this._actions = null;
    this._commandPoll = null;
    this._commandWatcher = null;
    this._publishTimer = null;
  }

  getName() {
    return "QuickshellVoiceStatus";
  }
  getVersion() {
    return "1.0.0";
  }
  getAuthor() {
    return "Luca";
  }
  getDescription() {
    return "Publish current VC to quickshell.";
  }

  _resolveStores() {
    const get = (name) => {
      try {
        return BdApi.Webpack.getStore(name);
      } catch (e) {
        return null;
      }
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

    const channelId = s.selected.getVoiceChannelId
      ? s.selected.getVoiceChannelId()
      : null;
    if (!channelId) return { inVoice: false };

    const states = s.voice.getVoiceStatesForChannel
      ? s.voice.getVoiceStatesForChannel(channelId) || {}
      : {};

    const ownId = s.users.getCurrentUser
      ? (s.users.getCurrentUser() || {}).id
      : null;

    const participants = [];
    for (const userId of Object.keys(states)) {
      const state = states[userId] || {};
      const user = s.users.getUser ? s.users.getUser(userId) : null;
      participants.push({
        id: String(userId),
        name: String(
          (user && (user.globalName || user.username)) ||
            state.nick ||
            state.username ||
            userId,
        ),
        avatar: this._avatarUrl(userId, user),
        self: ownId != null && String(userId) === String(ownId),
        mute: !!state.mute,
        selfMute: !!state.selfMute,
        deaf: !!state.deaf,
        selfDeaf: !!state.selfDeaf,
        video: !!state.selfVideo,
        streaming: !!state.selfStream,
        speaking:
          s.speaking && s.speaking.isSpeaking
            ? !!s.speaking.isSpeaking(userId)
            : false,
      });
    }

    participants.sort((a, b) => {
      if (a.self !== b.self) return a.self ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    const channel =
      s.channels && s.channels.getChannel
        ? s.channels.getChannel(channelId)
        : null;
    const guild =
      channel && channel.guild_id && s.guilds && s.guilds.getGuild
        ? s.guilds.getGuild(channel.guild_id)
        : null;

    return {
      inVoice: true,
      updatedAt: Date.now(),
      channel: channel ? String(channel.name || "") : "",
      guild: guild ? String(guild.name || "") : "",
      selfMute: s.media && s.media.isSelfMute ? !!s.media.isSelfMute() : false,
      selfDeaf: s.media && s.media.isSelfDeaf ? !!s.media.isSelfDeaf() : false,
      participants: participants,
    };
  }

  // BetterDiscord's fs shim has no async API, so writes stay synchronous;
  // _schedulePublish is what keeps them to one per 150ms during calls.
  _write(payload) {
    if (!this._fs || !this._statePath) return;
    const text = JSON.stringify(payload);
    if (text === this._lastPayload) return;
    this._lastPayload = text;
    try {
      const tmp = this._statePath + ".tmp";
      this._fs.writeFileSync(tmp, text);
      this._fs.renameSync(tmp, this._statePath);
    } catch (e) {}
  }

  _writeSync(payload) {
    if (!this._fs || !this._statePath) return;
    try {
      this._fs.writeFileSync(this._statePath, JSON.stringify(payload));
    } catch (e) {}
  }

  _runCommand(cmd) {
    const actions = this._actions || {};
    switch (cmd) {
      case "toggleSelfMute":
        if (typeof actions.toggleSelfMute === "function")
          actions.toggleSelfMute();
        break;
      case "toggleSelfDeaf":
        if (typeof actions.toggleSelfDeaf === "function")
          actions.toggleSelfDeaf();
        break;
      case "disconnect":
        this._disconnect();
        break;
      default:
        return;
    }
    this._lastPayload = "";
    this._publish();
  }

  // ChannelActions (exported as `default`) owns disconnect(); a plain
  // VOICE_CHANNEL_SELECT with no channel is the same thing at the dispatcher.
  _disconnect() {
    const W = BdApi.Webpack;
    const isActions = (m) =>
      m && typeof m.selectVoiceChannel === "function" && typeof m.disconnect === "function";
    let actions = null;
    try {
      actions = W.getModule(isActions, { searchExports: true });
    } catch (e) {}
    if (actions) {
      try {
        actions.disconnect();
        return;
      } catch (e) {
        console.error("[QuickshellVoiceStatus] disconnect() failed", e);
      }
    }
    try {
      const dispatcher = W.getModule((m) => m && typeof m.dispatch === "function" && typeof m.subscribe === "function",
        { searchExports: true });
      const selected = this._stores && this._stores.selected;
      dispatcher.dispatch({
        type: "VOICE_CHANNEL_SELECT",
        guildId: null,
        channelId: null,
        currentVoiceChannelId: selected ? selected.getVoiceChannelId() : null,
      });
    } catch (e) {
      console.error("[QuickshellVoiceStatus] no way to disconnect found", e);
    }
  }

  _pollCommands() {
    if (!this._fs || !this._commandPath) return;
    if (!this._fs.existsSync(this._commandPath)) return; // the normal case
    let text;
    try {
      text = this._fs.readFileSync(this._commandPath, "utf8");
    } catch (e) {
      return;
    }
    // Consumed before it is acted on, so a command that throws cannot be
    // replayed on every poll for the rest of the session.
    try {
      this._fs.unlinkSync(this._commandPath);
    } catch (e) {}
    for (const line of String(text).split("\n")) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        this._runCommand(JSON.parse(trimmed).cmd);
      } catch (e) {
        console.error("[QuickshellVoiceStatus] command failed", trimmed, e);
      }
    }
  }

  _publish() {
    try {
      this._write(this._snapshot());
    } catch (e) {
      this._write({ inVoice: false });
    }
  }

  // Speaking toggles many times a second in a call; one snapshot per 150ms is plenty.
  _schedulePublish() {
    if (this._publishTimer) return;
    this._publishTimer = setTimeout(() => {
      this._publishTimer = null;
      this._publish();
    }, 150);
  }

  _subscribe(store) {
    if (!store || typeof store.addChangeListener !== "function") return;
    const handler = () => this._schedulePublish();
    store.addChangeListener(handler);
    this._unsubscribes.push(() => {
      try {
        store.removeChangeListener(handler);
      } catch (e) {}
    });
  }

  start() {
    if (!this._runtimeDir) return;

    try {
      this._fs = require("fs");
    } catch (e) {
      return;
    }

    this._stores = this._resolveStores();
    try {
      this._actions = BdApi.Webpack.getByKeys(
        "toggleSelfMute",
        "toggleSelfDeaf",
      );
    } catch (e) {
      this._actions = null;
    }

    for (const key of ["voice", "speaking", "media", "selected"])
      this._subscribe(this._stores[key]);

    // Watch for commands; the slow poll only covers a watcher that died.
    try {
      this._commandWatcher = this._fs.watch(this._runtimeDir, (event, name) => {
        if (name === "quickshell-discord-cmd") this._pollCommands();
      });
    } catch (e) {
      this._commandWatcher = null;
    }
    this._commandPoll = setInterval(() => this._pollCommands(), this._commandWatcher ? 2000 : 250);

    this._heartbeat = setInterval(() => {
      if (
        this._stores &&
        this._stores.selected &&
        this._stores.selected.getVoiceChannelId &&
        this._stores.selected.getVoiceChannelId()
      ) {
        this._lastPayload = ""; // force a write so updatedAt advances
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
    if (this._commandWatcher) this._commandWatcher.close();
    this._commandWatcher = null;
    if (this._publishTimer) clearTimeout(this._publishTimer);
    this._publishTimer = null;
    this._lastPayload = "";
    this._writeSync({ inVoice: false });
  }
};
