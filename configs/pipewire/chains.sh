#!/usr/bin/env bash
# Renders one filter chain config on stdout: chains.sh lanes|eq. Each chain is
# its own client (pipewire-chain@<chain>.service), so stopping one leaves the
# server and the other chain alone.
#
# eq: the headset's AutoEq preset (pro-x-2.txt) as a wireplumber smart filter
# on the headset, so every stream bound for it passes the biquads: games
# directly, lanes through their default-sink output; other sinks never see it.
# IIR in the same graph cycle, no added latency; the passive output lets an
# idle headset suspend. The audio panel's eq switch enables or disables
# pipewire-chain@eq.service, which is also what persists it.
#
# lanes: loudness lanes.
# A lane is a virtual sink that claims media roles (device.intended-roles), so
# wireplumber routes every stream of that role into it; roles.conf gives the
# pulse apps their role. Unclaimed roles (games, system sounds) never touch a
# lane and stay on the hardware sink with zero added latency.
#
# Per lane:  in -> ebur128 -> x gain -> out
#            gain = fader * amount(clamp(lufs2gain(global lufs, target)))
#   meter   ebur128 "Global LUFS": gated integrated loudness over the history
#           window. the gate drops silence, so a voice lull holds the gain
#           instead of pumping it up; a louder onset takes over within one
#           400 ms block, a quieter passage only after the window drains
#           (fast attack, slow release, measured with pink noise steps)
#   range   clamp on the gain control, bounds both directions
#   amount  the leveler switch: Mult 1 Add 0 levels, Mult 0 Add 1 passes
#           unity. the quickshell audio panel flips it with pw-cli and
#           reads it back from pw-dump, so these names are its contract
#   fader   the lane's own volume, routed here by capture.volumes so it sits
#           after the leveler; as stream softvolume it would sit before it
#           and the leveler would undo every fader move
#
# Rejected: one shared leveler for all media evens out the sum, not music
# against voice. easyeffects needs lsp-plugins and runs every stream through
# it; ffmpeg loudnorm adds lookahead latency and is not realtime safe.
set -euo pipefail

# discord voice measured -18.4 lufs at unity: voice passes, normalized spotify (-14) drops 4 lu
readonly TARGET_LUFS=-18.0
# -12 db pulls a -6 lufs brickwalled master to target
readonly GAIN_MIN=0.25
# +6 db lifts a -24 lufs whisper; no limiter in the builtin graph, more boost clips speech peaks
readonly GAIN_MAX=2.0

# name|description|roles|history_s; media's window is song length so verse and chorus keep their dynamics
readonly LANES=(
    "media|Media|Music Movie|20.0"
    "voice|Voice|Communication Phone|10.0"
)

# AutoEq, Logitech G PRO X 2 LIGHTSPEED (leather earpads, the stock pads), measured by Filk, target Harman over-ear 2018,
# verbatim from jaakkopasanen/AutoEq@7ae0f56d53074872b028649617a22bbb4232feb7 results/Filk/over-ear/
# (only the first line is read as Preamp, a header comment would silently drop it and clip by 6.6 db)
EQ_PRESET="$(dirname "$(readlink -f "$0")")/pro-x-2.txt"
readonly EQ_PRESET
readonly EQ_TARGET="alsa_output.usb-Logitech_PRO_X_2_LIGHTSPEED_0000000000000000-00.analog-stereo"

lane_render() {
    local name="$1" description="$2" roles="$3" history_s="$4"
    local role role_list=""
    for role in ${roles}; do role_list+="\"${role}\" "; done
    cat <<EOF
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "${description}"
            media.name = "${description}"
            audio.position = [ FL FR ]
            filter.graph = {
                nodes = [
                    { type = ebur128 name = meter label = ebur128 config = { max-history = ${history_s} } }
                    { type = ebur128 name = target label = lufs2gain control = { "Target LUFS" = ${TARGET_LUFS} } }
                    { type = builtin name = range label = clamp control = { "Min" = ${GAIN_MIN} "Max" = ${GAIN_MAX} } }
                    { type = builtin name = amount label = linear control = { "Mult" = 1.0 "Add" = 0.0 } }
                    { type = builtin name = fader label = linear }
                    { type = builtin name = left label = linear }
                    { type = builtin name = right label = linear }
                ]
                links = [
                    { output = "meter:Out FL" input = "left:In" }
                    { output = "meter:Out FR" input = "right:In" }
                    { output = "meter:Global LUFS" input = "target:LUFS" }
                    { output = "target:Gain" input = "range:Control" }
                    { output = "range:Notify" input = "amount:Control" }
                    { output = "amount:Notify" input = "fader:Control" }
                    { output = "fader:Notify" input = "left:Mult" }
                    { output = "fader:Notify" input = "right:Mult" }
                ]
                inputs = [ "meter:In FL" "meter:In FR" ]
                outputs = [ "left:Out" "right:Out" ]
                capture.volumes = [ { control = "fader:Mult" } ]
            }
            capture.props = {
                node.name = "lane.${name}"
                media.class = Audio/Sink
                device.intended-roles = [ ${role_list}]
                # never the default sink, its own output would follow it
                priority.session = 0
            }
            playback.props = {
                node.name = "lane.${name}.out"
                # an idle lane must not keep the hardware sink awake
                node.passive = true
            }
        }
    }
EOF
}

eq_render() {
    cat <<EOF
    { name = libpipewire-module-parametric-equalizer
        args = {
            equalizer.filepath = "${EQ_PRESET}"
            equalizer.description = "EQ"
            audio.channels = 2
            audio.position = [ FL FR ]
            capture.props = {
                node.name = "eq"
                media.class = Audio/Sink
                filter.smart = true
                filter.smart.name = "eq"
                filter.smart.target = { node.name = "${EQ_TARGET}" }
            }
            playback.props = { node.name = "eq.out" node.passive = true }
        }
    }
EOF
}

lanes_render() {
    local lane name description roles history_s
    for lane in "${LANES[@]}"; do
        IFS='|' read -r name description roles history_s <<<"${lane}"
        lane_render "${name}" "${description}" "${roles}" "${history_s}"
    done
}

case "${1:-}" in
    lanes | eq) render="${1}_render" ;;
    *)
        echo "usage: chains.sh lanes|eq" >&2
        exit 1
        ;;
esac

cat <<EOF
# generated by configs/pipewire/chains.sh, edit there
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
EOF
"${render}"
echo "]"
