-- every app's playback runs through a loopback of its own: app -> app.<key> (Audio/Sink) -> app.<key>.out -> device,
-- so a capture of the app's ports (obs) keeps full level while .out carries the system volume, mute and route.
-- run by wpexec (app-loopback.service) outside wireplumber; listening to obs (dot.obs-listen) mutes every loopback.

PREFIX = "app."
OUT_SUFFIX = ".out"
STATE_NAME = "app-loopback"
STATE_LISTEN = "listen."
STATE_OWN = "own."
STATE_SEEN = "seen."
-- dotted, like every other bookkeeping key: the start loop treats a dotless key as an app
STATE_EPOCH = "state.epoch"
-- an own-level record no stream reclaimed within this many service starts is dropped, so a stale one never levels an
-- unrelated stream of the app days later
OWN_EPOCHS_KEPT = 2
-- an app no stream played from within this many service starts loses its loopback, so one-off players (installers,
-- paplay) don't keep a sink pair forever
APP_EPOCHS_KEPT = 20
LISTEN_KEY = "dot.obs-listen"
OBS_BINARY = "obs"
SETTLE_MS = 300
RETRY_MS = 100
RETRY_COUNT_MAX = 20
VOLUME_FULL = 1.0
VOLUME_EPSILON = 0.0001
RELEASE_TIMEOUT_MS = 3000

args = ...
release = args ~= nil and args:parse().release == true
state = State(STATE_NAME)
known = state:load()
loopbacks = {}
installed = false

nodes_om = ObjectManager({ Interest({ type = "node" }) })
metadata_om = ObjectManager({ Interest({ type = "metadata", Constraint({ "metadata.name", "=", "default" }) }) })
links_om = ObjectManager({ Interest({ type = "link" }) })
clients_om = ObjectManager({
    Interest({ type = "client", Constraint({ "application.process.binary", "=", OBS_BINARY, type = "pw" }) }),
})

-- The loopback key of a stream, nil for one that keeps its route: its own target, a notification, a filter or loopback.
function stream_key(props)
    if props["node.link-group"] or props["stream.monitor"] == "true" then
        return nil
    end
    if props["target.object"] or props["node.target"] then
        return nil
    end
    if props["media.role"] == "Notification" then
        return nil
    end
    -- obs's monitoring is the listen path itself, which the muted loopbacks must not silence
    if props["application.process.binary"] == OBS_BINARY then
        return nil
    end
    local name = props["application.name"] or props["application.process.binary"] or props["node.name"]
    if not name then
        return nil
    end
    local key = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if key == "" then
        return nil
    end
    return key, name
end

function out_key(node)
    local name = node.properties["node.name"] or ""
    if name:sub(1, #PREFIX) ~= PREFIX or name:sub(-#OUT_SUFFIX) ~= OUT_SUFFIX then
        return nil
    end
    return name:sub(#PREFIX + 1, -#OUT_SUFFIX - 1)
end

function loopback_create(key, name)
    if loopbacks[key] then
        return
    end
    local channels = Json.Array({ "FL", "FR" })
    local args = Json.Object({
        -- distinct from the app: port aliases are "<description>:<port>", and pw-link resolves those
        ["node.description"] = name .. " (system)",
        ["audio.position"] = channels,
        ["capture.props"] = Json.Object({
            ["node.name"] = PREFIX .. key,
            ["media.name"] = PREFIX .. key,
            ["media.class"] = "Audio/Sink",
            ["audio.position"] = channels,
        }),
        -- passive like the eq's output, so an idle loopback lets the device suspend
        ["playback.props"] = Json.Object({
            ["node.name"] = PREFIX .. key .. OUT_SUFFIX,
            ["media.name"] = PREFIX .. key .. OUT_SUFFIX,
            ["node.passive"] = true,
            ["audio.position"] = channels,
        }),
    })
    loopbacks[key] = LocalModule("libpipewire-module-loopback", args:get_data(), {})
    if known[key] ~= name then
        known[key] = name
        state:save_after_timeout(known)
    end
    Log.info("loopback " .. PREFIX .. key .. " for " .. name)
end

function node_find(name)
    return nodes_om:lookup({ Constraint({ "node.name", "=", name }) })
end

function node_get(id)
    return nodes_om:lookup({ Constraint({ "bound-id", "=", id, type = "gobject" }) })
end

-- A target.object value, an object.serial or a node.name, as the node it names; nil for a node gone since.
function target_node(value)
    if not value or value == "-1" then
        return nil
    end
    return nodes_om:lookup({ Constraint({ "object.serial", "=", value, type = "pw-global" }) }) or node_find(value)
end

function link_contains(output_id, input_id)
    return links_om:lookup({
        Constraint({ "link.output.node", "=", output_id, type = "pw-global" }),
        Constraint({ "link.input.node", "=", input_id, type = "pw-global" }),
    }) ~= nil
end

function retry(fn, retries)
    if retries < RETRY_COUNT_MAX then
        Core.timeout_add(RETRY_MS, function()
            fn(retries + 1)
            return false
        end)
    end
end

-- A node's Props as { levels = per channel volume times the master volume, mute = bool }.
function level_get(node, fn)
    node:enum_params("Props", function(it, err)
        if err then
            return
        end
        for p in it:iterate() do
            local props = p:parse().properties
            if props and props.channelVolumes then
                local levels = {}
                for i, v in ipairs(props.channelVolumes) do
                    levels[i] = v * (props.volume or VOLUME_FULL)
                end
                fn({ levels = levels, mute = props.mute == true })
                return
            end
        end
    end)
end

function level_set(node, levels, mute)
    local list = { "Spa:Float" }
    for _, v in ipairs(levels) do
        table.insert(list, v)
    end
    node:set_param(
        "Props",
        Pod.Object({
            "Spa:Pod:Object:Param:Props",
            "Props",
            volume = VOLUME_FULL,
            mute = mute,
            channelVolumes = Pod.Array(list),
        })
    )
end

function level_mean(levels)
    local sum = 0
    for _, v in ipairs(levels) do
        sum = sum + v
    end
    return #levels > 0 and sum / #levels or VOLUME_FULL
end

function level_scale(levels, factor)
    local scaled = {}
    for i, v in ipairs(levels) do
        scaled[i] = v * factor
    end
    return scaled
end

function level_full(levels)
    local ones = {}
    for i in ipairs(levels) do
        ones[i] = VOLUME_FULL
    end
    return ones
end

function mute_set(node, mute)
    node:set_param("Props", Pod.Object({ "Spa:Pod:Object:Param:Props", "Props", mute = mute }))
end

-- The levels the stop handed out, by loopback key, node name and media name (a serial dies with the pipewire session):
-- "<key> <epoch> <loopback level> <own level>...", one own level per stream that shares all three, taken in order.
function own_mark(props, key)
    return STATE_OWN .. key .. "." .. (props["node.name"] or "") .. "." .. (props["media.name"] or "")
end

function own_parse(record)
    local fields = {}
    for field in (record or ""):gmatch("%S+") do
        fields[#fields + 1] = field
    end
    if #fields < 4 then
        return nil
    end
    local owns = {}
    for i = 4, #fields do
        owns[#owns + 1] = tonumber(fields[i])
    end
    return { key = fields[1], epoch = tonumber(fields[2]) or 0, loop = tonumber(fields[3]) or VOLUME_FULL, owns = owns }
end

function own_format(record)
    local owns = {}
    for i, own in ipairs(record.owns) do
        owns[i] = tostring(own)
    end
    return record.key .. " " .. record.epoch .. " " .. record.loop .. " " .. table.concat(owns, " ")
end

function epoch_current()
    return tonumber(known[STATE_EPOCH]) or 0
end

-- each start is a new epoch; records older than OWN_EPOCHS_KEPT starts go
function epoch_advance()
    local epoch = epoch_current() + 1
    local changes = {}
    for mark, value in pairs(known) do
        if mark:sub(1, #STATE_OWN) == STATE_OWN then
            local record = own_parse(value)
            if not record or record.epoch < epoch - OWN_EPOCHS_KEPT then
                changes[mark] = false
            end
        elseif not mark:find(".", 1, true) then
            local seen = tonumber(known[STATE_SEEN .. mark])
            if seen == nil then
                changes[STATE_SEEN .. mark] = tostring(epoch)
            elseif seen < epoch - APP_EPOCHS_KEPT then
                changes[mark] = false
                changes[STATE_SEEN .. mark] = false
            end
        end
    end
    -- applied after the walk: a table must not grow while pairs() walks it
    for mark, value in pairs(changes) do
        known[mark] = value or nil
    end
    known[STATE_EPOCH] = tostring(epoch)
    state:save_after_timeout(known)
end

-- A stream the stop handed a level to gives it back to its loopback once it plays into it (on the device it would jump);
-- a stream without a record keeps its level, which is the app's own slider.
function level_reclaim(stream_id, sink_id, out_id, retries)
    local stream, out = node_get(stream_id), node_get(out_id)
    if not (stream and out) then
        return
    end
    local mark = own_mark(stream.properties, stream_key(stream.properties) or "")
    local record = own_parse(known[mark])
    if not record or record.key ~= stream_key(stream.properties) then
        return
    end
    if not link_contains(stream_id, sink_id) then
        retry(function(r)
            level_reclaim(stream_id, sink_id, out_id, r)
        end, retries)
        return
    end
    -- each stream of that name takes one own level; the loopback gets the level the stop recorded, the same for all
    local own = table.remove(record.owns, 1)
    known[mark] = #record.owns > 0 and own_format(record) or nil
    state:save_after_timeout(known)
    level_get(stream, function(handed)
        level_get(out, function(loop)
            level_set(out, level_scale(level_full(loop.levels), record.loop), handed.mute)
            level_set(stream, level_scale(level_full(handed.levels), own), false)
            Log.info("gave the level of " .. stream.properties["node.name"] .. " back to its loopback")
        end)
    end)
end

function stream_attach(id, retries, reclaim)
    local stream = node_get(id)
    if not stream then
        return
    end
    local key = stream_key(stream.properties)
    if not key then
        return
    end
    local sink = node_find(PREFIX .. key)
    local out = node_find(PREFIX .. key .. OUT_SUFFIX)
    local metadata = metadata_om:lookup()
    if not (sink and out and metadata) then
        retry(function(r)
            stream_attach(id, r, reclaim)
        end, retries)
        return
    end
    local serial = sink.properties["object.serial"]
    local current = metadata:find(id, "target.object")
    if current ~= serial and current ~= sink.properties["node.name"] then
        local target = target_node(current)
        local target_name = target and target.properties["node.name"] or ""
        if target and target_name:sub(1, #PREFIX) ~= PREFIX then
            metadata:set(out["bound-id"], "target.object", "Spa:Id", target.properties["object.serial"])
        end
        metadata:set(id, "target.object", "Spa:Id", serial)
    end
    if reclaim then
        level_reclaim(id, sink["bound-id"], out["bound-id"], 0)
    end
end

function listen_active()
    local metadata = metadata_om:lookup()
    return metadata ~= nil and metadata:find(0, LISTEN_KEY) ~= nil and clients_om:lookup() ~= nil
end

-- Mutes every loopback while obs listens; only the ones muted here are recorded, so a user's own mute stays.
function listen_apply()
    local active = listen_active()
    for node in nodes_om:iterate({ Constraint({ "node.name", "matches", PREFIX .. "*" .. OUT_SUFFIX }) }) do
        local mark = STATE_LISTEN .. out_key(node)
        if not active and known[mark] then
            mute_set(node, false)
            known[mark] = nil
            state:save_after_timeout(known)
        elseif active and not known[mark] then
            level_get(node, function(loop)
                if not loop.mute and listen_active() and not known[mark] then
                    mute_set(node, true)
                    known[mark] = "true"
                    state:save_after_timeout(known)
                end
            end)
        end
    end
end

-- The stop: every looped stream takes its loopback's level times its own and the mute, the loopback goes to full;
-- the stream's own level is recorded so the next start can split them again.
function release_all()
    local pending = 0
    local function done()
        pending = pending - 1
        if pending == 0 then
            state:save(known)
            Core.sync(function()
                Core.quit()
            end)
        end
    end
    pending = 1
    for out in nodes_om:iterate({ Constraint({ "node.name", "matches", PREFIX .. "*" .. OUT_SUFFIX }) }) do
        local key = out_key(out)
        local sink = node_find(PREFIX .. key)
        if sink then
            pending = pending + 1
            level_get(out, function(loop)
                local listened = known[STATE_LISTEN .. key] ~= nil
                local mute = loop.mute and not listened
                local level = level_mean(loop.levels)
                local handed = false
                local into_sink = {
                    Constraint({ "link.input.node", "=", sink["bound-id"], type = "pw-global" }),
                }
                -- one link per channel: each stream once
                local seen = {}
                for link in links_om:iterate(into_sink) do
                    local stream_id = tonumber(link.properties["link.output.node"])
                    local stream = not seen[stream_id] and node_get(stream_id) or nil
                    seen[stream_id] = true
                    if stream then
                        handed = true
                        pending = pending + 1
                        level_get(stream, function(own)
                            local mark = own_mark(stream.properties, key)
                            local record = own_parse(known[mark])
                            if not record or record.epoch ~= epoch_current() then
                                record = { key = key, epoch = epoch_current(), loop = level, owns = {} }
                            end
                            record.owns[#record.owns + 1] = level_mean(own.levels)
                            known[mark] = own_format(record)
                            level_set(stream, level_scale(own.levels, level), mute)
                            done()
                        end)
                    end
                end
                if handed then
                    level_set(out, level_full(loop.levels), false)
                elseif listened then
                    mute_set(out, false)
                end
                known[STATE_LISTEN .. key] = nil
                done()
            end)
        end
    end
    done()
end

if release then
    nodes_om:connect("installed", function()
        Core.sync(release_all)
    end)
    Core.timeout_add(RELEASE_TIMEOUT_MS, function()
        Core.quit()
        return false
    end)
    links_om:activate()
    nodes_om:activate()
    return
end

metadata_om:connect("object-added", function(_, metadata)
    metadata:connect("changed", function(_, subject, key)
        if subject == 0 and key == LISTEN_KEY then
            listen_apply()
            return
        end
        if key ~= "target.object" or not installed then
            return
        end
        local node = node_get(subject)
        if node and node.properties["media.class"] == "Stream/Output/Audio" and stream_key(node.properties) then
            stream_attach(subject, 0, false)
        end
    end)
    listen_apply()
end)
clients_om:connect("object-added", listen_apply)
clients_om:connect("object-removed", listen_apply)

nodes_om:connect("object-added", function(_, node)
    if out_key(node) then
        listen_apply()
        return
    end
    if node.properties["media.class"] ~= "Stream/Output/Audio" then
        return
    end
    local key, name = stream_key(node.properties)
    if not key then
        return
    end
    loopback_create(key, name)
    local epoch = tostring(epoch_current())
    if known[STATE_SEEN .. key] ~= epoch then
        known[STATE_SEEN .. key] = epoch
        state:save_after_timeout(known)
    end
    local id = node["bound-id"]
    if not installed then
        stream_attach(id, 0, true)
        return
    end
    -- state-stream restores the target at node-added; act after it
    Core.timeout_add(SETTLE_MS, function()
        stream_attach(id, 0, true)
        return false
    end)
end)
nodes_om:connect("installed", function()
    installed = true
    listen_apply()
end)
epoch_advance()

for key, name in pairs(known) do
    if not key:find(".", 1, true) then
        loopback_create(key, name)
    end
end
links_om:activate()
clients_om:activate()
metadata_om:activate()
nodes_om:activate()
