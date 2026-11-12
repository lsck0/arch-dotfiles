/**
 * @name QuickshellVoiceStatus
 * @author Luca
 * @version 1.1.0
 * @description Publish the current VC to quickshell and take its mute, deafen and disconnect commands.
 * @source https://github.com/lsck0/arch-dotfiles
 */

const COMMAND_FILE = "quickshell-discord-cmd";

module.exports = class QuickshellVoiceStatus {
  constructor() {
    this._stores = null;
    this._unsubscribes = [];
    this._heartbeat = null;
    this._lastPayload = "";
    this._fs = null;
    this._runtimeDir = (typeof process !== "undefined" && process.env && process.env.XDG_RUNTIME_DIR) || null;
    // used only once start() found the runtime dir
    this._statePath = this._runtimeDir + "/quickshell-discord-voice.json";
    this._commandPath = this._runtimeDir + "/" + COMMAND_FILE;
    this._commandPoll = null;
    this._commandWatcher = null;
    this._publishTimer = null;
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
      rtc: get("RTCConnectionStore"),
    };
  }

  // SelectedChannelStore only knows guild voice channels; a DM or group call has no guild voice channel, so fall back
  // to the RTC connection, which tracks both
  _voiceChannelId() {
    const s = this._stores;
    return s?.selected?.getVoiceChannelId?.() || s?.rtc?.getChannelId?.() || null;
  }

  _avatarUrl(userId, user) {
    if (user?.avatar) {
      const ext = String(user.avatar).startsWith("a_") ? "gif" : "png";
      return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=64`;
    }
    const id = String(user?.id || userId || "");
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
    if (!s?.voice || !s.users) return { inVoice: false };

    const channelId = this._voiceChannelId();
    if (!channelId) return { inVoice: false };

    const states = s.voice.getVoiceStatesForChannel?.(channelId) || {};
    const ownId = s.users.getCurrentUser?.()?.id;
    const participants = Object.keys(states).map((userId) => {
      const state = states[userId] || {};
      const user = s.users.getUser?.(userId);
      return {
        id: String(userId),
        name: String(user?.globalName || user?.username || state.nick || state.username || userId),
        avatar: this._avatarUrl(userId, user),
        self: ownId != null && String(userId) === String(ownId),
        mute: !!state.mute,
        selfMute: !!state.selfMute,
        deaf: !!state.deaf,
        selfDeaf: !!state.selfDeaf,
        video: !!state.selfVideo,
        streaming: !!state.selfStream,
        speaking: !!s.speaking?.isSpeaking?.(userId),
      };
    });
    participants.sort((a, b) => (a.self !== b.self ? (a.self ? -1 : 1) : a.name.localeCompare(b.name)));

    const channel = s.channels?.getChannel?.(channelId);
    const guild = channel?.guild_id ? s.guilds?.getGuild?.(channel.guild_id) : null;
    return {
      inVoice: true,
      updatedAt: Date.now(),
      channel: String(channel?.name || ""),
      guild: String(guild?.name || ""),
      selfMute: !!s.media?.isSelfMute?.(),
      selfDeaf: !!s.media?.isSelfDeaf?.(),
      participants,
    };
  }

  _write(payload) {
    if (!this._fs) return;
    const text = JSON.stringify(payload);
    if (text === this._lastPayload) return;
    this._lastPayload = text;
    try {
      const tmp = this._statePath + ".tmp";
      this._fs.writeFileSync(tmp, text);
      this._fs.renameSync(tmp, this._statePath);
    } catch (e) {}
  }

  _runCommand(cmd) {
    const has = (...fns) => (m) => m && fns.every((f) => typeof m[f] === "function");
    if (cmd === "toggleSelfMute" || cmd === "toggleSelfDeaf") {
      const type = cmd === "toggleSelfMute" ? "AUDIO_TOGGLE_SELF_MUTE" : "AUDIO_TOGGLE_SELF_DEAF";
      this._invoke(cmd, has(cmd), { type, context: "default", syncRemote: true });
    } else if (cmd === "disconnect") {
      this._invoke(cmd, has("selectVoiceChannel", "disconnect"), {
        type: "VOICE_CHANNEL_SELECT",
        guildId: null,
        channelId: null,
        currentVoiceChannelId: this._voiceChannelId(),
      });
    } else {
      return;
    }
    this._lastPayload = "";
    this._publish();
  }

  // Looked up per command, not once at start: Discord loads its audio and voice actions lazily and renames their
  // module's keys between client builds. The flux action is the fallback when no module exposes the function.
  _invoke(name, isActions, fluxAction) {
    const W = BdApi.Webpack;
    try {
      const actions = W.getModule(isActions, { searchExports: true });
      if (actions) return actions[name]();
    } catch (e) {
      console.error(`[QuickshellVoiceStatus] ${name}() failed`, e);
    }
    try {
      W.getModule((m) => m && typeof m.dispatch === "function" && typeof m.subscribe === "function",
        { searchExports: true }).dispatch(fluxAction);
    } catch (e) {
      console.error(`[QuickshellVoiceStatus] ${name}: no action module and no dispatcher`, e);
    }
  }

  _pollCommands() {
    if (!this._fs) return;
    if (!this._fs.existsSync(this._commandPath)) return;
    // claim the file by renaming first, so a line appended between read and delete is not lost
    const pending = this._commandPath + ".reading";
    try {
      this._fs.renameSync(this._commandPath, pending);
    } catch (e) {
      return;
    }
    let text;
    try {
      text = this._fs.readFileSync(pending, "utf8");
    } catch (e) {
      return;
    } finally {
      try {
        this._fs.unlinkSync(pending);
      } catch (e) {}
    }
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

  _fallbackToPoll() {
    if (this._commandWatcher) {
      try {
        this._commandWatcher.close();
      } catch (e) {}
      this._commandWatcher = null;
    }
    if (!this._commandPoll) this._commandPoll = setInterval(() => this._pollCommands(), 250);
  }

  _publish() {
    try {
      this._write(this._snapshot());
    } catch (e) {
      this._write({ inVoice: false });
    }
  }

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

    for (const key of ["voice", "speaking", "media", "selected", "rtc"])
      this._subscribe(this._stores[key]);

    try {
      if (this._fs.existsSync(this._commandPath)) this._fs.unlinkSync(this._commandPath);
    } catch (e) {}

    try {
      this._commandWatcher = this._fs.watch(this._runtimeDir, (event, name) => {
        if (name === COMMAND_FILE) this._pollCommands();
      });
      // a watcher that errors stops firing for good: fall back to polling instead of going deaf
      this._commandWatcher.on("error", (e) => {
        console.error("[QuickshellVoiceStatus] command watcher failed, polling instead", e);
        this._fallbackToPoll();
      });
    } catch (e) {
      this._commandWatcher = null;
    }
    // the watcher covers live changes; poll only as a fallback when fs.watch failed
    if (!this._commandWatcher) this._fallbackToPoll();

    this._heartbeat = setInterval(() => {
      if (this._voiceChannelId()) {
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
    this._write({ inVoice: false });
  }
};
