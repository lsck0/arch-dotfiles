"""Sidebar panel (View3D > N > Generate) over the comfy-gen command (llm/comfyui).

Texture: a prompt becomes a seamless PBR set, box-projected onto the selected meshes, so no UVs are needed.
Mesh: a prompt or an image file becomes a Hunyuan3D mesh, imported at the cursor.
comfy-gen runs in a thread; a timer picks its result up on Blender's main thread.
"""

import json
import os
import subprocess
import threading

import bpy

COMFY_GEN = os.path.expanduser("~/.local/bin/comfy-gen")
POLL_S = 0.5
# box projection's seam softening and the texture's world size: one tile per this many metres
BOX_BLEND = 0.25
TILE_M = 1.0

_job = {"thread": None, "result": None, "error": None, "kind": None, "targets": []}


def _run(kind, args):
    try:
        out = subprocess.run([COMFY_GEN, kind, "--json", *args], capture_output=True, text=True, check=False)
        if out.returncode != 0:
            _job["error"] = (out.stderr.strip().splitlines() or ["comfy-gen failed"])[-1]
        else:
            _job["result"] = json.loads(out.stdout.strip().splitlines()[-1])
    except (OSError, ValueError, IndexError) as e:
        _job["error"] = str(e)


def _image(path, colorspace):
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    return img


def _material(result, name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0 / TILE_M,) * 3
    links.new(coords.outputs["Object"], mapping.inputs["Vector"])

    def tex(path, colorspace, y):
        node = nodes.new("ShaderNodeTexImage")
        node.image = _image(path, colorspace)
        node.projection = "BOX"
        node.projection_blend = BOX_BLEND
        node.location = (-500, y)
        links.new(mapping.outputs["Vector"], node.inputs["Vector"])
        return node

    links.new(tex(result["albedo"], "sRGB", 300).outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex(result["roughness"], "Non-Color", 0).outputs["Color"], bsdf.inputs["Roughness"])
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.location = (-200, -300)
    links.new(tex(result["normal"], "Non-Color", -300).outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    coords.location, mapping.location = (-1100, 0), (-800, 0)
    return mat


def _finish():
    if _job["thread"] is not None and _job["thread"].is_alive():
        return POLL_S
    scene = bpy.context.scene
    _job["thread"] = None
    if _job["error"]:
        scene.comfy_status = "failed: " + _job["error"]
        return None
    result = _job["result"]
    if _job["kind"] == "texture":
        mat = _material(result, "gen-" + os.path.basename(result["dir"]))
        for name in _job["targets"]:
            obj = bpy.data.objects.get(name)
            if obj is not None and obj.type == "MESH":
                obj.data.materials.clear()
                obj.data.materials.append(mat)
        scene.comfy_status = "textured: " + os.path.basename(result["dir"])
    else:
        bpy.ops.import_scene.gltf(filepath=result["mesh"])
        scene.comfy_status = "imported: " + os.path.basename(result["mesh"])
    return None


def _start(kind, args, targets=()):
    _job.update(result=None, error=None, kind=kind, targets=list(targets))
    _job["thread"] = threading.Thread(target=_run, args=(kind, args), daemon=True)
    _job["thread"].start()
    bpy.app.timers.register(_finish, first_interval=POLL_S)


class COMFY_OT_texture(bpy.types.Operator):
    bl_idname = "comfy.texture"
    bl_label = "Texture Selected"
    bl_description = "Generate a seamless PBR texture from the prompt and put it on the selected meshes"

    @classmethod
    def poll(cls, context):
        return (
            _job["thread"] is None
            and context.scene.comfy_prompt.strip()
            and any(o.type == "MESH" for o in context.selected_objects)
        )

    def execute(self, context):
        targets = [o.name for o in context.selected_objects if o.type == "MESH"]
        context.scene.comfy_status = "generating texture..."
        _start("texture", [context.scene.comfy_prompt], targets)
        return {"FINISHED"}


class COMFY_OT_mesh(bpy.types.Operator):
    bl_idname = "comfy.mesh"
    bl_label = "Generate Mesh"
    bl_description = "Generate a mesh from the image file if one is set, else from the prompt, and import it"

    @classmethod
    def poll(cls, context):
        scene = context.scene
        return _job["thread"] is None and (scene.comfy_prompt.strip() or scene.comfy_image)

    def execute(self, context):
        scene = context.scene
        image = bpy.path.abspath(scene.comfy_image) if scene.comfy_image else ""
        source = image if image and os.path.isfile(image) else scene.comfy_prompt
        scene.comfy_status = "generating mesh (minutes)..."
        _start("3d", [source])
        return {"FINISHED"}


class COMFY_PT_panel(bpy.types.Panel):
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Generate"
    bl_label = "Comfy Generate"

    def draw(self, context):
        scene, layout = context.scene, self.layout
        layout.prop(scene, "comfy_prompt", text="")
        layout.operator(COMFY_OT_texture.bl_idname, icon="TEXTURE")
        layout.separator()
        layout.prop(scene, "comfy_image", text="Image")
        layout.operator(COMFY_OT_mesh.bl_idname, icon="MESH_MONKEY")
        if scene.comfy_status:
            layout.label(text=scene.comfy_status)


CLASSES = (COMFY_OT_texture, COMFY_OT_mesh, COMFY_PT_panel)


def register():
    bpy.types.Scene.comfy_prompt = bpy.props.StringProperty(name="Prompt", description="What to generate")
    bpy.types.Scene.comfy_image = bpy.props.StringProperty(
        name="Image", subtype="FILE_PATH", description="Reference image for a mesh; empty uses the prompt"
    )
    bpy.types.Scene.comfy_status = bpy.props.StringProperty(name="Status")
    for cls in CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
    del bpy.types.Scene.comfy_prompt, bpy.types.Scene.comfy_image, bpy.types.Scene.comfy_status
