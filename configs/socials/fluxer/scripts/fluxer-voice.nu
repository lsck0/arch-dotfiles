#!/usr/bin/env -S nu --no-config-file
# Fluxer's voice call as desktop/quickshell's Fluxer widget reads it: one DevTools connection to the running client
# (DEVTOOLS_PORT in mod.nu), a page script subscribed to its media engine that pushes each change through a CDP binding,
# written to STATE in the Discord plugin's shape. Exits when Fluxer is not running or closes; fluxer-voice.service
# starts it again.

const PORT = 9234
const BINDING = "qsFluxerVoice"
const STATE_FILE = "quickshell-fluxer-voice.json"
# a websocket frame holds a whole snapshot, avatars urls and all
const FRAME_BYTES = 4194304
# Fluxer not running is the normal idle state, not a failure: a clean exit keeps failure-notify quiet, Restart=always
# still brings the helper back
const EXIT_NO_CLIENT = 0

# Runs in Fluxer's page, once per document. Its engine facade (window._mediaEngineFacade) holds the call and fires
# subscribe on every change; names come from its channel and guild stores, avatars from its avatar url helper, looked up
# by the module ids of this release first and by shape after an update moved them. A snapshot goes out only when it
# changed, and every HEARTBEAT ms while in a call so the widget's stale check (50 s) holds.
const PAGE_SCRIPT = '
(() => {
  if (window.__qsFluxerVoice) { window.__qsFluxerVoice.publish(true); return; }
  const HEARTBEAT = 20000, COALESCE = 150, IDS = { channels: "97441", guilds: "16321", avatars: "438931" };
  let req = null, stores = null, last = "", pending = false;
  const send = (text) => { try { window.qsFluxerVoice(text); } catch (e) {} };
  const findStores = () => {
    if (stores) return stores;
    if (!req) { try { window.rspackChunkfluxer_app.push([[Symbol("qs-voice")], {}, (r) => { req = r; }]); } catch (e) {} }
    if (!req) return {};
    const pick = (ids, test) => {
      for (const id of ids) {
        let e; try { e = req(id); } catch (x) { continue; }
        for (const k of Object.keys(e || {})) { try { if (test(e[k])) return e[k]; } catch (x) {} }
      }
      return null;
    };
    const store = (fn) => (v) => v && typeof v === "object" && typeof v[fn] === "function";
    const avatar = (v) => typeof v === "function" && Function.prototype.toString.call(v).includes("\"avatars\"")
      && /\/avatars\/1\/abc\.png/.test(String(v({ id: "1", avatar: "abc" })));
    const find = (id, test) => pick([id], test) || pick(Object.keys(req.m), test);
    stores = { channels: find(IDS.channels, store("getChannel")), guilds: find(IDS.guilds, store("getGuild")),
      avatar: find(IDS.avatars, avatar) };
    return stores;
  };
  const snapshot = () => {
    const f = window._mediaEngineFacade;
    if (!f || !f.connected || !f.channelId) return { inVoice: false };
    const s = findStores();
    const me = (f.getCurrentUserVoiceState && f.getCurrentUserVoiceState()) || {};
    const speaking = new Set(Object.values(f.participants || {}).filter((p) => p.isSpeaking).map((p) => String(p.userId)));
    const seen = new Set();
    const participants = [];
    for (const st of Object.values(f.getAllVoiceStatesInChannel(f.guildId, f.channelId) || {})) {
      const id = String(st.user_id);
      if (seen.has(id)) continue;
      seen.add(id);
      const u = (st.member && st.member.user) || {};
      participants.push({
        id, name: String((st.member && st.member.nick) || u.global_name || u.username || id),
        avatar: u.avatar && s.avatar ? String(s.avatar({ id, avatar: u.avatar })).replace(/size=\d+/, "size=64") : "",
        self: id === String(me.user_id), mute: !!st.mute, selfMute: !!st.self_mute, deaf: !!st.deaf,
        selfDeaf: !!st.self_deaf, video: !!st.self_video, streaming: !!st.self_stream, speaking: speaking.has(id),
      });
    }
    participants.sort((a, b) => (a.self !== b.self ? (a.self ? -1 : 1) : a.name.localeCompare(b.name)));
    const channel = s.channels && s.channels.getChannel(f.channelId);
    const guild = f.guildId && s.guilds ? s.guilds.getGuild(f.guildId) : null;
    return { inVoice: true, channel: String((channel && channel.name) || ""), guild: String((guild && guild.name) || ""),
      selfMute: !!me.self_mute, selfDeaf: !!me.self_deaf, participants };
  };
  const publish = (force) => {
    let snap;
    try { snap = snapshot(); } catch (e) { snap = { inVoice: false }; }
    const key = JSON.stringify(snap);
    if (!force && key === last) return;
    last = key;
    send(JSON.stringify(snap.inVoice ? Object.assign({ updatedAt: Date.now() }, snap) : snap));
  };
  const changed = () => {
    if (pending) return;
    pending = true;
    setTimeout(() => { pending = false; publish(false); }, COALESCE);
  };
  window.__qsFluxerVoice = { publish };
  const start = () => {
    const f = window._mediaEngineFacade;
    if (!f || typeof f.subscribe !== "function") { setTimeout(start, 2000); return; }
    f.subscribe(changed);
    setInterval(() => { if (last.startsWith("{\"inVoice\":true")) publish(true); }, HEARTBEAT);
    publish(true);
  };
  start();
})();
'

def state-write [path: path, text: string]: nothing -> nothing {
    let tmp = $"($path).tmp"
    $text | save --force --raw $tmp
    mv --force $tmp $path
}

def main [] {
    let state = $env.XDG_RUNTIME_DIR | path join $STATE_FILE
    let pages = try { http get --max-time 3sec $"http://127.0.0.1:($PORT)/json/list" } catch { exit $EXIT_NO_CLIENT }
    let page = $pages | where type == "page" | get --optional 0
    if $page == null { exit $EXIT_NO_CLIENT }
    # the binding survives reloads; the script added for new documents comes back with each one, the evaluate covers
    # the document already open
    let init = [
        {id: 1, method: "Runtime.addBinding", params: {name: $BINDING}}
        {id: 2, method: "Page.addScriptToEvaluateOnNewDocument", params: {source: $PAGE_SCRIPT}}
        {id: 3, method: "Runtime.evaluate", params: {expression: $PAGE_SCRIPT}}
    ] | each { to json --raw } | str join "\n"
    # -n keeps the socket open after the init lines; it ends when Fluxer closes it
    $"($init)\n" | ^websocat -n -B $FRAME_BYTES --text $page.webSocketDebuggerUrl | lines | each {|line|
        let msg = try { $line | from json } catch { null }
        if $msg != null and $msg.method? == "Runtime.bindingCalled" and $msg.params?.name? == $BINDING {
            state-write $state $msg.params.payload
        }
    } | ignore
    state-write $state '{"inVoice":false}'
    exit $EXIT_NO_CLIENT
}
