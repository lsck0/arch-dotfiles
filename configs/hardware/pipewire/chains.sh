#!/usr/bin/env bash
# renders one filter chain on stdout: chains.sh lanes|eq. each chain is its own client
# (pipewire-chain@<chain>.service), so stopping one leaves the server and the other alone.
# eq: the headset AutoEq preset (pro-x-2.txt) as a wireplumber smart filter on the headset; iir, no added
# latency, passive output lets an idle headset suspend. the audio panel's eq switch owns pipewire-chain@eq.
# lanes: a lane is a virtual sink claiming media roles (device.intended-roles); roles.conf gives pulse apps
# their role, wireplumber routes each role into its lane. unclaimed roles (games, system sounds) stay on the
# hardware sink, zero added latency.
#   chain:  in -> ebur128 -> x gain -> out,  gain = fader * amount(clamp(lufs2gain(global lufs, target)))
#   ebur128 "Global LUFS": gated integrated loudness, so a voice lull holds gain instead of pumping
#   amount: leveler switch, Mult 1 Add 0 levels / Mult 0 Add 1 unity; the quickshell panel's contract via pw-cli/pw-dump
#   fader:  the lane volume, routed by capture.volumes to sit after the leveler
# not easyeffects (pulls lsp-plugins, per-stream) or ffmpeg loudnorm (lookahead latency, not realtime safe)
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
# generated by configs/hardware/pipewire/chains.sh, edit there
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
