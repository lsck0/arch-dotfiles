#!/usr/bin/env -S nu --no-config-file
# Generation through the local ComfyUI's API, no editor needed: a tileable PBR texture set, an image, or a 3D mesh.
# Results land under ~/pictures/comfyui; --json prints the paths for scripts and the Blender panel.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [xdg]

const HERE = path self | path expand | path dirname
const URL = "http://127.0.0.1:8188"
const POLL = 1sec
# the first request socket-starts ComfyUI and loads the checkpoint; a 3D run then takes minutes on a 16 GB card
const TIMEOUT = 20min
const FLUX = "flux1-schnell-fp8.safetensors"
const HUNYUAN = "hunyuan_3d_v2.1.safetensors"
const TEXTURE_STYLE = "seamless tileable texture, flat top-down view, even diffuse lighting, no shadows, no perspective, highly detailed surface"
# Hunyuan3D reads a cast shadow or a floor as geometry, so the reference is a cutout; object-prep.py keys it out by the
# background's colour, on chroma green since no drawn object has it (on white or grey, flux's light grey for "mid-grey",
# a white or cream object vanished)
const OBJECT_STYLE = "single isolated object, centered, whole object in frame, on a solid flat pure chroma key green screen background, no shadow, no floor, no ground plane, even studio lighting"

def python []: nothing -> path { xdg data comfyui venv bin python }

def output-dir []: nothing -> path { $nu.home-dir | path join pictures comfyui }

def slug [text: string]: nothing -> string {
    $text | str lowercase | str replace --all --regex '[^a-z0-9]+' "-" | str trim --char "-" | str substring 0..<40
}

def seed []: nothing -> int { random int 0..2147483647 }

def flux-graph [prompt: string, width: int, height: int, prefix: string]: nothing -> record {
    {
        "1": {class_type: CheckpointLoaderSimple, inputs: {ckpt_name: $FLUX}}
        "2": {class_type: CLIPTextEncode, inputs: {text: $prompt, clip: ["1" 1]}}
        "3": {class_type: CLIPTextEncode, inputs: {text: "", clip: ["1" 1]}}
        "4": {class_type: EmptySD3LatentImage, inputs: {width: $width, height: $height, batch_size: 1}}
        # schnell is distilled: 4 steps, cfg 1 (the negative prompt does nothing)
        "5": {class_type: KSampler, inputs: {
            seed: (seed), steps: 4, cfg: 1.0, sampler_name: euler, scheduler: simple, denoise: 1.0
            model: ["1" 0], positive: ["2" 0], negative: ["3" 0], latent_image: ["4" 0]
        }}
        "6": {class_type: VAEDecode, inputs: {samples: ["5" 0], vae: ["1" 2]}}
        "7": {class_type: SaveImage, inputs: {filename_prefix: $prefix, images: ["6" 0]}}
    }
}

# the "Hunyuan3D 2.1" template's subgraph, flattened: shape only (core ComfyUI has no texture stage)
def hunyuan-graph [image: string, prefix: string]: nothing -> record {
    {
        "1": {class_type: LoadImage, inputs: {image: $image}}
        "2": {class_type: ImageOnlyCheckpointLoader, inputs: {ckpt_name: $HUNYUAN}}
        "3": {class_type: ModelSamplingAuraFlow, inputs: {model: ["2" 0], shift: 1.0, sampling: flow}}
        "4": {class_type: CLIPVisionEncode, inputs: {clip_vision: ["2" 1], image: ["1" 0], crop: center}}
        "5": {class_type: Hunyuan3Dv2Conditioning, inputs: {clip_vision_output: ["4" 0]}}
        "6": {class_type: EmptyLatentHunyuan3Dv2, inputs: {resolution: 4096, batch_size: 1}}
        "7": {class_type: KSampler, inputs: {
            seed: (seed), steps: 30, cfg: 5.0, sampler_name: euler, scheduler: normal, denoise: 1.0
            model: ["3" 0], positive: ["5" 0], negative: ["5" 1], latent_image: ["6" 0]
        }}
        "8": {class_type: VAEDecodeHunyuan3D, inputs: {samples: ["7" 0], vae: ["2" 2], num_chunks: 8000, octree_resolution: 256}}
        "9": {class_type: VoxelToMesh, inputs: {voxel: ["8" 0], algorithm: "surface net", threshold: 0.6}}
        "10": {class_type: SaveGLB, inputs: {mesh: ["9" 0], filename_prefix: $prefix}}
    }
}

def status [msg: string]: nothing -> nothing { print --stderr $"comfy-gen: ($msg)" }

# Queues a graph and waits for it; the paths of every file it saved.
def run-graph [graph: record]: nothing -> list<string> {
    let queued = try {
        http post --content-type application/json $"($URL)/prompt" {prompt: $graph, client_id: "comfy-gen"}
    } catch {|e|
        error make {msg: $"comfy-gen: ComfyUI did not take the job at ($URL) \(systemctl --user status comfyui.socket\): ($e.msg)"}
    }
    let id = $queued.prompt_id
    let deadline = (date now) + $TIMEOUT
    mut entry: any = null
    while $entry == null {
        if (date now) > $deadline { error make {msg: $"comfy-gen: no result after ($TIMEOUT)"} }
        sleep $POLL
        let found = http get $"($URL)/history/($id)" | get --optional $id
        if $found != null and ($found.status?.completed? == true or $found.status?.status_str? == "error") { $entry = $found }
    }
    if $entry.status.status_str == "error" {
        let why = $entry.status.messages | where {|m| $m.0 == execution_error } | get --optional 0.1.exception_message
        error make {msg: $"comfy-gen: ComfyUI failed: ($why | default 'see journalctl --user -u comfyui')"}
    }
    $entry.outputs | values | each {|o| $o | values | flatten } | flatten
    | where {|f| ($f | describe | str starts-with record) and $f.filename? != null }
    | each {|f| output-dir | path join $f.subfolder $f.filename }
}

def emit [result: record, json: bool]: nothing -> nothing {
    if $json { print ($result | to json --raw) } else { $result | transpose key value | each { print $"($in.key): ($in.value)" } | ignore }
}

# An image from a prompt.
def "main image" [
    ...prompt: string
    --size: int = 1024  # square edge in pixels, a multiple of 16
    --json              # print the result as json
]: nothing -> nothing {
    let text = $prompt | str join " "
    status $"image: ($text)"
    let files = run-graph (flux-graph $text $size $size $"images/(slug $text)")
    emit {image: ($files | first)} $json
}

# A seamless PBR set (albedo, normal, roughness, height) from a prompt, in its own folder.
def "main texture" [
    ...prompt: string
    --size: int = 1024  # square edge in pixels, a multiple of 16
    --json              # print the result as json
]: nothing -> nothing {
    let text = $prompt | str join " "
    status $"texture: ($text)"
    let name = $"(slug $text)-(date now | format date '%Y%m%d-%H%M%S')"
    let raw = run-graph (flux-graph $"($text), ($TEXTURE_STYLE)" $size $size $"textures/($name)/raw") | first
    let dir = $raw | path dirname
    ^(python) ($HERE | path join pbr-maps.py) $raw $dir
    rm $raw
    emit {
        dir: $dir, albedo: ($dir | path join albedo.png), normal: ($dir | path join normal.png)
        roughness: ($dir | path join roughness.png), height: ($dir | path join height.png)
    } $json
}

# A 3D mesh (.glb, untextured) from an image file or, when the argument is no file, a prompt.
def "main 3d" [
    ...source: string
    --open  # open the mesh in Blender when done
    --json  # print the result as json
]: nothing -> nothing {
    let text = $source | str join " "
    let given = ($source | length) == 1 and ($text | path expand | path exists)
    let image = if $given { $text | path expand } else {
        status $"reference image: ($text)"
        run-graph (flux-graph $"($text), ($OBJECT_STYLE)" 1024 1024 $"3d/(slug $text)-ref") | first
    }
    # flux still loaded makes comfyui's free_memory fail loading hunyuan (IndexError in model_management): unload first
    try { http post --content-type application/json $"($URL)/free" {unload_models: true, free_memory: true} | ignore } catch { }
    # LoadImage reads ComfyUI's input dir; the recentred copy there needs no upload
    let input = xdg data comfyui input
    mkdir $input
    let staged = $"comfy-gen-(date now | format date '%Y%m%d-%H%M%S')-($image | path parse | get stem).png"
    ^(python) ($HERE | path join object-prep.py) $image ($input | path join $staged)
    status "mesh: Hunyuan3D 2.1"
    let label = if $given { $image | path parse | get stem | slug $in } else { slug $text }
    let mesh = run-graph (hunyuan-graph $staged $"3d/($label)") | where ($it | str ends-with ".glb") | first
    rm --force ($input | path join $staged)
    if $open { ^uwsm-app -- blender --python-expr $"import bpy; bpy.ops.wm.read_homefile\(use_empty=True\); bpy.ops.import_scene.gltf\(filepath=r'($mesh)'\)" }
    emit {mesh: $mesh, reference: $image} $json
}

def main []: nothing -> nothing {
    print "comfy-gen texture <prompt> | 3d <image|prompt> [--open] | image <prompt>   (--json for scripts)"
}
