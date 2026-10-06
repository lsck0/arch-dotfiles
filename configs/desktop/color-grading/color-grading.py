#!/usr/bin/env python3
"""Color grading in the display hardware: one owner for every output's KMS CTM and gamma LUT.

Grading used to be a full-screen compositor shader, which kept the gpu rendering every frame,
blocked direct scanout and added latency. The display engine applies the 3x3 color transform
matrix (CTM) and then the per-channel gamma LUT to every scanned-out pixel for free, so the daemon
uploads both once per output and sleeps in select until an output, or a setting, changes.

Presets (PRESETS below, the single list; toggles and the bar read it through `list` / `status`):
    off        identity everywhere
    default    contrast 1.05 around mid grey, black point 0.010, gamma 1.07, 6000K
    reading    4500K, contrast 0.92, blacks lifted to 4%: paper-like, low strain
    grayscale  every channel gets Rec.709 luma, then the default curve
    red-night  red channel carries luma, green and blue are dark, dimmed to 55%: keeps dark adaptation
Night light (4000K) and brightness compose with any preset: CTM = brightness * whitepoint * preset.
The whitepoint is the warmer of the preset's and the night light's, never both multiplied.

State: the preset persists ($XDG_STATE_HOME/color-grading/preset). Night light and brightness are
volatile ($XDG_RUNTIME_DIR/color-grading/) so a reboot starts in daylight at full brightness.
The files are the source of truth; `set` writes them and reloads the service, the daemon rereads
them on SIGHUP (systemd ExecReload), so nothing polls and a stopped daemon loses nothing.

Overview:
    curve_apply(x, curve)              tone curve on one encoded channel value in [0, 1]
    ramp_create(size, curve)           red, green and blue ramps as one wire-ready table
    matrix_for_kelvin(kelvin)          hyprsunset's blackbody whitepoint, so night light looks the same
    settings_load() / settings_save()  parse the state files into Settings, write them atomically
    ctm_compose(settings)              the matrix sent for every output
    daemon_run(client)                 dispatch wayland events and reloads forever

Example:
    color-grading.py run                     # the daemon, what color-grading.service runs
    color-grading.py list                    # preset names in cycle order
    color-grading.py set preset reading      # also: set nightlight on, set brightness -5
    color-grading.py status                  # json for the bar: settings plus the preset table

Hyprland resets CTM and LUT when the client disconnects, so stopping or crashing the daemon is a
clean off switch. Hyprland lets only the first CTM client own it: hyprsunset must not run.

Rejected alternatives:
    - saturation boost and vibrance: saturation > 1 needs negative off-diagonal CTM entries, which
      hyprland-ctm-control-v1 rejects (CTMControl.cpp: el < 0 is invalid_matrix), vibrance is not
      linear at all, the monitors' DDC/CI has no saturation VCP (0x8A), and Hyprland exposes no KMS
      3D LUT. The vivid screen shader (toggle-shader.sh) is the opt-in for that.
    - hyprsunset: temperature and a brightness scalar only, no arbitrary matrix for grayscale or red.
    - wl-gammactl, gammastep, wlsunset, wl-gammarelay-rs: temperature, brightness or a bare gamma
      exponent, none takes contrast around mid grey with a black point.
    - pywayland: not packaged in the arch repos and needs a scanner step for wlr protocols; the
      handful of messages used here are cheaper written against the wire format directly.
    - a control socket: the state files are needed for persistence anyway, a second channel that
      can disagree with them would be two sources of truth.
"""

from __future__ import annotations

import argparse
import dataclasses
import itertools
import json
import math
import os
import selectors
import signal
import socket
import struct
import subprocess
import sys

# -----------------------------------------------------------------------------
# TYPES
# -----------------------------------------------------------------------------

Matrix = tuple[float, float, float, float, float, float, float, float, float]


@dataclasses.dataclass(frozen=True)
class Curve:
    """Per-channel tone curve: contrast around mid grey, black point, gamma, then the output range."""

    contrast: float
    blackpoint: float
    gamma: float
    floor: float
    ceiling: float


@dataclasses.dataclass(frozen=True)
class Preset:
    name: str
    label: str
    curve: Curve
    # row-major, applied to the encoded rgb before the whitepoint
    matrix: Matrix
    # None is a neutral whitepoint
    kelvin: int | None


@dataclasses.dataclass(frozen=True)
class Settings:
    preset: Preset
    nightlight: bool
    brightness_percent: int


@dataclasses.dataclass
class Output:
    global_name: int
    output_id: int
    version: int
    control_id: int | None = None
    gamma_size: int | None = None
    name: str = "?"


@dataclasses.dataclass
class Client:
    sock: socket.socket
    registry_id: int
    sync_id: int
    id_next: int
    settings: Settings
    synced: bool = False
    gamma_manager_id: int | None = None
    ctm_manager_id: int | None = None
    ctm_blocked: bool = False
    # registry global name -> output, plus object id -> output for event routing
    outputs: dict[int, Output] = dataclasses.field(default_factory=dict)
    objects: dict[int, Output] = dataclasses.field(default_factory=dict)
    # wl_output globals seen before the initial sync
    outputs_pending: list[tuple[int, int]] = dataclasses.field(default_factory=list)
    inbox: bytearray = dataclasses.field(default_factory=bytearray)


class ProtocolError(Exception):
    """The compositor sent something this client cannot continue from."""


# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------

MID_GREY = 0.5
IDENTITY: Matrix = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
# ITU-R BT.709 luma weights, the primaries sRGB shares
LUMA = (0.2126, 0.7152, 0.0722)
CURVE_IDENTITY = Curve(contrast=1.0, blackpoint=0.0, gamma=1.0, floor=0.0, ceiling=1.0)
# the former color-correction.frag screen shader, minus its saturation and vibrance
CURVE_DEFAULT = Curve(contrast=1.05, blackpoint=0.010, gamma=1.07, floor=0.0, ceiling=1.0)

PRESETS: dict[str, Preset] = {
    p.name: p
    for p in (
        Preset("off", "Off", CURVE_IDENTITY, IDENTITY, None),
        Preset("default", "Default", CURVE_DEFAULT, IDENTITY, 6000),
        Preset("reading", "Reading", Curve(contrast=0.92, blackpoint=0.0, gamma=1.0, floor=0.04, ceiling=1.0), IDENTITY, 4500),
        Preset("grayscale", "Grayscale", CURVE_DEFAULT, LUMA * 3, None),
        Preset("red-night", "Red night", Curve(contrast=1.0, blackpoint=0.0, gamma=1.1, floor=0.0, ceiling=0.55),
               (*LUMA, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), None),
    )
}
PRESET_DEFAULT = PRESETS["default"]
# the CTM protocol only takes entries >= 0, which is why no preset can raise saturation
assert all(v >= 0 and math.isfinite(v) for p in PRESETS.values() for v in p.matrix)
assert all(0 <= p.curve.floor < p.curve.ceiling <= 1 and p.curve.contrast > 0 for p in PRESETS.values())

# 4000K matches the former nightlight.frag whitepoint
NIGHT_KELVIN = 4000
KELVIN_MIN, KELVIN_MAX = 1000, 20000
BRIGHTNESS_PERCENT_DEFAULT = 100
# hyprsunset's --gamma_max 150 this replaces; above 100 the CTM clips highlights
BRIGHTNESS_PERCENT_MAX = 150

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "color-grading")
RUNTIME_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "color-grading")
PRESET_PATH = os.path.join(STATE_DIR, "preset")
NIGHTLIGHT_PATH = os.path.join(RUNTIME_DIR, "nightlight")
BRIGHTNESS_PATH = os.path.join(RUNTIME_DIR, "brightness")
UNIT = "color-grading.service"

RAMP_VALUE_MAX = 0xFFFF
# KMS reports GAMMA_LUT_SIZE (amdgpu 4096, i915 up to 1024); the bound only rejects nonsense
GAMMA_SIZE_MAX = 1 << 16
# wl_fixed is signed 24.8
FIXED_ONE = 256

WL_DISPLAY_ID = 1
# libwayland's server-side ids start here, a client id must stay below
CLIENT_ID_MAX = 0xFEFFFFFF
HEADER_SIZE_BYTES = 8
RECV_SIZE_BYTES = 4096

WL_DISPLAY_SYNC = 0
WL_DISPLAY_GET_REGISTRY = 1
WL_DISPLAY_EVENT_ERROR = 0
WL_DISPLAY_EVENT_DELETE_ID = 1
WL_REGISTRY_BIND = 0
WL_REGISTRY_EVENT_GLOBAL = 0
WL_REGISTRY_EVENT_GLOBAL_REMOVE = 1
WL_CALLBACK_EVENT_DONE = 0
WL_OUTPUT_RELEASE = 0
WL_OUTPUT_EVENT_NAME = 4
WL_OUTPUT_VERSION_RELEASE = 3
WL_OUTPUT_VERSION_NAME = 4
GAMMA_MANAGER_GET_GAMMA_CONTROL = 0
GAMMA_CONTROL_SET_GAMMA = 0
GAMMA_CONTROL_DESTROY = 1
GAMMA_CONTROL_EVENT_GAMMA_SIZE = 0
GAMMA_CONTROL_EVENT_FAILED = 1
CTM_MANAGER_SET_CTM_FOR_OUTPUT = 0
CTM_MANAGER_COMMIT = 1
CTM_MANAGER_EVENT_BLOCKED = 0
# version 2 adds the blocked event
CTM_MANAGER_VERSION = 2

WL_OUTPUT = "wl_output"
GAMMA_MANAGER = "zwlr_gamma_control_manager_v1"
CTM_MANAGER = "hyprland_ctm_control_manager_v1"

# -----------------------------------------------------------------------------
# INTERNAL
# -----------------------------------------------------------------------------


def log(message: str) -> None:
    print(f"color-grading: {message}", file=sys.stderr, flush=True)


def wire_uint(value: int) -> bytes:
    assert 0 <= value <= 0xFFFFFFFF
    return struct.pack("=I", value)


def wire_fixed(value: float) -> bytes:
    assert math.isfinite(value) and value >= 0
    return struct.pack("=i", round(value * FIXED_ONE))


def wire_string(text: str) -> bytes:
    data = text.encode() + b"\0"
    return wire_uint(len(data)) + data + b"\0" * (-len(data) % 4)


def wire_string_decode(payload: bytes, offset: int) -> tuple[str, int]:
    if offset + 4 > len(payload):
        raise ProtocolError("string length past end of message")
    (length,) = struct.unpack_from("=I", payload, offset)
    start, end = offset + 4, offset + 4 + length
    if length == 0 or end > len(payload) or payload[end - 1] != 0:
        raise ProtocolError("malformed string")
    return payload[start : end - 1].decode(errors="replace"), start + length + (-length % 4)


def file_read(path: str) -> str | None:
    try:
        with open(path) as fh:
            return fh.read().strip()
    except FileNotFoundError:
        return None


def file_write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as fh:
        fh.write(text + "\n")
    os.replace(path + ".tmp", path)


def matrix_multiply(a: Matrix, b: Matrix) -> Matrix:
    product = tuple(sum(a[row * 3 + k] * b[k * 3 + col] for k in range(3)) for row in range(3) for col in range(3))
    assert len(product) == 9
    return product  # type: ignore[return-value]


def matrix_scale(s: float) -> Matrix:
    return (s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, s)


def client_id_allocate(client: Client) -> int:
    # ids are never reused: outputs come and go a handful of times per session
    object_id = client.id_next
    assert object_id < CLIENT_ID_MAX
    client.id_next += 1
    return object_id


def client_request(client: Client, object_id: int, opcode: int, payload: bytes = b"", fd: int | None = None) -> None:
    size = HEADER_SIZE_BYTES + len(payload)
    assert size % 4 == 0 and size <= 0xFFFF
    message = wire_uint(object_id) + wire_uint(size << 16 | opcode) + payload
    if fd is None:
        client.sock.sendall(message)
    else:
        sent = socket.send_fds(client.sock, [message], [fd])
        assert sent == len(message)


def client_bind(client: Client, global_name: int, interface: str, version: int) -> int:
    object_id = client_id_allocate(client)
    payload = wire_uint(global_name) + wire_string(interface) + wire_uint(version) + wire_uint(object_id)
    client_request(client, client.registry_id, WL_REGISTRY_BIND, payload)
    return object_id


# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------


def curve_apply(x: float, curve: Curve) -> float:
    """Contrast around mid grey, black point, gamma, then squeeze into [floor, ceiling]."""
    assert 0.0 <= x <= 1.0
    y = (x - MID_GREY) * curve.contrast + MID_GREY
    y = max(y - curve.blackpoint, 0.0) / (1.0 - curve.blackpoint)
    y = min(y, 1.0) ** curve.gamma
    y = curve.floor + (curve.ceiling - curve.floor) * y
    assert 0.0 <= y <= 1.0
    return y


def ramp_create(size: int, curve: Curve) -> bytes:
    """Red, green and blue ramps back to back as native-endian uint16, the layout set_gamma expects."""
    assert 2 <= size <= GAMMA_SIZE_MAX
    ramp = [round(curve_apply(i / (size - 1), curve) * RAMP_VALUE_MAX) for i in range(size)]
    assert all(a <= b for a, b in itertools.pairwise(ramp))
    table = struct.pack(f"={size}H", *ramp) * 3
    assert len(table) == size * 3 * 2
    return table


def matrix_for_kelvin(kelvin: int) -> Matrix:
    """Tanner Helland's blackbody fit exactly as hyprsunset computes it, integer hundreds included."""
    assert KELVIN_MIN <= kelvin <= KELVIN_MAX
    t = kelvin // 100
    if t <= 66:
        r = 255.0
        g = min(max(99.4708025861 * math.log(t) - 161.1195681661, 0.0), 255.0)
        b = 0.0 if t <= 19 else min(max(math.log(t - 10) * 138.5177312231 - 305.0447927307, 0.0), 255.0)
    else:
        r = min(max(329.698727446 * (t - 60) ** -0.1332047592, 0.0), 255.0)
        g = min(max(288.1221695283 * (t - 60) ** -0.0755148492, 0.0), 255.0)
        b = 255.0
    return (r / 255, 0.0, 0.0, 0.0, g / 255, 0.0, 0.0, 0.0, b / 255)


def ctm_compose(settings: Settings) -> Matrix:
    kelvins = [k for k in (settings.preset.kelvin, NIGHT_KELVIN if settings.nightlight else None) if k is not None]
    whitepoint = matrix_for_kelvin(min(kelvins)) if kelvins else IDENTITY
    ctm = matrix_multiply(matrix_scale(settings.brightness_percent / 100), matrix_multiply(whitepoint, settings.preset.matrix))
    assert all(v >= 0 and math.isfinite(v) for v in ctm)
    return ctm


def preset_parse(text: str) -> Preset:
    if text not in PRESETS:
        raise ValueError(f"unknown preset {text!r}, expected one of {', '.join(PRESETS)}")
    return PRESETS[text]


def nightlight_parse(text: str) -> bool:
    if text not in ("on", "off"):
        raise ValueError(f"nightlight must be on or off, got {text!r}")
    return text == "on"


def brightness_parse(text: str, current_percent: int) -> int:
    """Absolute percent, or a +N / -N step from the current value, clamped like hyprsunset's gamma."""
    if not text.lstrip("+-").isdigit():
        raise ValueError(f"brightness must be N, +N or -N percent, got {text!r}")
    value = current_percent + int(text) if text[0] in "+-" else int(text)
    return min(max(value, 0), BRIGHTNESS_PERCENT_MAX)


def settings_load() -> Settings:
    """Missing files are defaults; a corrupt one is logged and replaced by its default, never fatal."""
    values = {}
    for key, path, parse, default in (
        ("preset", PRESET_PATH, preset_parse, PRESET_DEFAULT),
        ("nightlight", NIGHTLIGHT_PATH, nightlight_parse, False),
        ("brightness_percent", BRIGHTNESS_PATH, lambda t: brightness_parse(t, 0), BRIGHTNESS_PERCENT_DEFAULT),
    ):
        text = file_read(path)
        try:
            values[key] = default if text is None else parse(text)
        except ValueError as error:
            log(f"{path}: {error}, using the default")
            values[key] = default
    return Settings(**values)


def settings_save(settings: Settings) -> None:
    file_write(PRESET_PATH, settings.preset.name)
    file_write(NIGHTLIGHT_PATH, "on" if settings.nightlight else "off")
    file_write(BRIGHTNESS_PATH, str(settings.brightness_percent))


def output_attach(client: Client, global_name: int, version: int) -> None:
    assert client.synced and global_name not in client.outputs
    bound = min(version, WL_OUTPUT_VERSION_NAME)
    output = Output(global_name=global_name, output_id=client_bind(client, global_name, WL_OUTPUT, bound), version=bound)
    client.outputs[global_name] = output
    client.objects[output.output_id] = output
    if client.gamma_manager_id is not None:
        output.control_id = client_id_allocate(client)
        client_request(client, client.gamma_manager_id, GAMMA_MANAGER_GET_GAMMA_CONTROL,
                       wire_uint(output.control_id) + wire_uint(output.output_id))
        client.objects[output.control_id] = output


def output_control_destroy(client: Client, output: Output) -> None:
    if output.control_id is None:
        return
    client_request(client, output.control_id, GAMMA_CONTROL_DESTROY)
    output.control_id = None
    output.gamma_size = None


def output_detach(client: Client, global_name: int) -> None:
    output = client.outputs.pop(global_name)
    output_control_destroy(client, output)
    if output.version >= WL_OUTPUT_VERSION_RELEASE:
        client_request(client, output.output_id, WL_OUTPUT_RELEASE)
    log(f"{output.name}: gone")


def output_lut_upload(client: Client, output: Output) -> None:
    """Hand the ramp over in a memfd; Hyprland read()s it from the shared file offset, hence the rewind."""
    assert output.control_id is not None and output.gamma_size is not None
    fd = os.memfd_create("color-grading", os.MFD_CLOEXEC)
    try:
        table = ramp_create(output.gamma_size, client.settings.preset.curve)
        assert os.write(fd, table) == len(table)
        os.lseek(fd, 0, os.SEEK_SET)
        client_request(client, output.control_id, GAMMA_CONTROL_SET_GAMMA, fd=fd)
    finally:
        os.close(fd)


def ctm_commit(client: Client) -> None:
    """Every output in one commit: the protocol resets any output left out to identity."""
    if client.ctm_manager_id is None or client.ctm_blocked:
        return
    ctm = ctm_compose(client.settings)
    for output in client.outputs.values():
        payload = wire_uint(output.output_id) + b"".join(wire_fixed(v) for v in ctm)
        client_request(client, client.ctm_manager_id, CTM_MANAGER_SET_CTM_FOR_OUTPUT, payload)
    client_request(client, client.ctm_manager_id, CTM_MANAGER_COMMIT)


def client_apply(client: Client) -> None:
    for output in client.outputs.values():
        if output.gamma_size is not None:
            output_lut_upload(client, output)
    ctm_commit(client)
    s = client.settings
    log(f"preset {s.preset.name}, nightlight {'on' if s.nightlight else 'off'}, brightness {s.brightness_percent}%")


def client_synced(client: Client) -> None:
    """The initial registry burst is complete: every global the compositor had is known."""
    assert not client.synced
    client.synced = True
    if client.gamma_manager_id is None:
        log(f"compositor does not offer {GAMMA_MANAGER}, no tone curve")
    if client.ctm_manager_id is None:
        log(f"compositor does not offer {CTM_MANAGER}, no matrix, whitepoint or brightness")
    for global_name, version in client.outputs_pending:
        output_attach(client, global_name, version)
    client.outputs_pending.clear()
    ctm_commit(client)


def event_dispatch(client: Client, object_id: int, opcode: int, payload: bytes) -> None:
    if object_id == WL_DISPLAY_ID:
        if opcode == WL_DISPLAY_EVENT_ERROR:
            (failed_id, code), (message, _) = struct.unpack_from("=II", payload), wire_string_decode(payload, 8)
            raise ProtocolError(f"compositor error on object {failed_id}, code {code}: {message}")
        if opcode != WL_DISPLAY_EVENT_DELETE_ID:
            raise ProtocolError(f"unknown wl_display event {opcode}")
    elif object_id == client.registry_id:
        if opcode == WL_REGISTRY_EVENT_GLOBAL:
            (global_name,) = struct.unpack_from("=I", payload)
            interface, offset = wire_string_decode(payload, 4)
            (version,) = struct.unpack_from("=I", payload, offset)
            if interface == GAMMA_MANAGER and client.gamma_manager_id is None:
                client.gamma_manager_id = client_bind(client, global_name, GAMMA_MANAGER, 1)
            elif interface == CTM_MANAGER and client.ctm_manager_id is None:
                client.ctm_manager_id = client_bind(client, global_name, CTM_MANAGER, min(version, CTM_MANAGER_VERSION))
            elif interface == WL_OUTPUT and client.synced:
                output_attach(client, global_name, version)
                ctm_commit(client)
            elif interface == WL_OUTPUT:
                client.outputs_pending.append((global_name, version))
        elif opcode == WL_REGISTRY_EVENT_GLOBAL_REMOVE:
            (global_name,) = struct.unpack_from("=I", payload)
            if global_name in client.outputs:
                output_detach(client, global_name)
        else:
            raise ProtocolError(f"unknown wl_registry event {opcode}")
    elif object_id == client.sync_id:
        if opcode != WL_CALLBACK_EVENT_DONE:
            raise ProtocolError(f"unknown wl_callback event {opcode}")
        client_synced(client)
    elif object_id == client.ctm_manager_id:
        if opcode != CTM_MANAGER_EVENT_BLOCKED:
            raise ProtocolError(f"unknown {CTM_MANAGER} event {opcode}")
        # set requests from a blocked manager are dropped silently, so stop sending them
        client.ctm_blocked = True
        log("another client owns the CTM (hyprsunset still running?), no matrix, whitepoint or brightness")
    elif object_id in client.objects:
        output = client.objects[object_id]
        if object_id == output.output_id:
            if opcode == WL_OUTPUT_EVENT_NAME:
                output.name, _ = wire_string_decode(payload, 0)
        elif object_id != output.control_id:
            pass  # events still in flight for a control already destroyed
        elif opcode == GAMMA_CONTROL_EVENT_GAMMA_SIZE:
            (size,) = struct.unpack_from("=I", payload)
            if not 2 <= size <= GAMMA_SIZE_MAX:
                log(f"{output.name}: gamma size {size} out of range, no tone curve")
                output_control_destroy(client, output)
                return
            output.gamma_size = size
            output_lut_upload(client, output)
            log(f"{output.name}: graded ({size} entries)")
        elif opcode == GAMMA_CONTROL_EVENT_FAILED:
            # another gamma client owns this output, it has no LUT, or it is being unplugged
            log(f"{output.name}: gamma control refused")
            output_control_destroy(client, output)
        else:
            raise ProtocolError(f"unknown zwlr_gamma_control_v1 event {opcode}")
    elif object_id >= client.id_next:
        raise ProtocolError(f"event for object {object_id} that was never created")


def client_connect(settings: Settings) -> Client:
    display = os.environ.get("WAYLAND_DISPLAY")
    if not display:
        raise ProtocolError("WAYLAND_DISPLAY is unset, not inside a wayland session")
    path = display if display.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), display)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM | socket.SOCK_CLOEXEC)
    try:
        sock.connect(path)
    except OSError as error:
        sock.close()
        raise ProtocolError(f"cannot connect to {path}: {error.strerror}") from error
    # the first two client ids, handed out in request order
    client = Client(sock=sock, registry_id=WL_DISPLAY_ID + 1, sync_id=WL_DISPLAY_ID + 2, id_next=WL_DISPLAY_ID + 3,
                    settings=settings)
    client_request(client, WL_DISPLAY_ID, WL_DISPLAY_GET_REGISTRY, wire_uint(client.registry_id))
    client_request(client, WL_DISPLAY_ID, WL_DISPLAY_SYNC, wire_uint(client.sync_id))
    return client


def client_receive(client: Client) -> None:
    data = client.sock.recv(RECV_SIZE_BYTES)
    if not data:
        raise ProtocolError("compositor closed the connection")
    client.inbox += data
    while len(client.inbox) >= HEADER_SIZE_BYTES:
        object_id, word = struct.unpack_from("=II", client.inbox)
        size, opcode = word >> 16, word & 0xFFFF
        if size < HEADER_SIZE_BYTES or size % 4:
            raise ProtocolError(f"malformed message size {size}")
        if len(client.inbox) < size:
            break
        payload = bytes(client.inbox[HEADER_SIZE_BYTES:size])
        del client.inbox[:size]
        event_dispatch(client, object_id, opcode, payload)


def daemon_run(client: Client, wake: socket.socket) -> None:
    """Blocks in select: wayland events, or a SIGHUP byte on the wakeup socket meaning the state files changed."""
    selector = selectors.DefaultSelector()
    selector.register(client.sock, selectors.EVENT_READ)
    selector.register(wake, selectors.EVENT_READ)
    while True:
        for key, _ in selector.select():
            if key.fileobj is wake:
                wake.recv(RECV_SIZE_BYTES)
                client.settings = settings_load()
                client_apply(client)
            else:
                client_receive(client)


def command_run() -> int:
    # handler before anything slow: an early reload must not hit SIGHUP's default action, which kills
    wake, wake_write = socket.socketpair()
    wake_write.setblocking(False)
    signal.set_wakeup_fd(wake_write.fileno())
    signal.signal(signal.SIGHUP, lambda *_: None)
    try:
        client = client_connect(settings_load())
        log(f"preset {client.settings.preset.name}")
        daemon_run(client, wake)
    except ProtocolError as error:
        log(str(error))
        return 1
    except KeyboardInterrupt:
        return 0
    raise AssertionError("daemon_run only returns by raising")


def command_set(key: str, value: str) -> int:
    settings = settings_load()
    try:
        if key == "preset":
            settings = dataclasses.replace(settings, preset=preset_parse(value))
        elif key == "nightlight":
            settings = dataclasses.replace(settings, nightlight=nightlight_parse(value))
        else:
            assert key == "brightness"
            settings = dataclasses.replace(settings, brightness_percent=brightness_parse(value, settings.brightness_percent))
    except ValueError as error:
        log(str(error))
        return 2
    settings_save(settings)
    # no-op while the daemon is stopped, it reads the files when it starts
    subprocess.run(["systemctl", "--user", "--quiet", "try-reload-or-restart", UNIT], check=False)
    return 0


def command_get(key: str) -> int:
    settings = settings_load()
    if key == "preset":
        print(settings.preset.name)
    elif key == "nightlight":
        print("on" if settings.nightlight else "off")
    else:
        assert key == "brightness"
        print(settings.brightness_percent)
    return 0


def command_status() -> int:
    settings = settings_load()
    print(json.dumps({
        "preset": settings.preset.name,
        "nightlight": settings.nightlight,
        "brightness": settings.brightness_percent,
        "presets": [{"name": p.name, "label": p.label} for p in PRESETS.values()],
    }))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Color grading in the display CTM and gamma LUT.")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("run", help="the daemon: own CTM and gamma LUT of every output, reload on SIGHUP")
    commands.add_parser("list", help="preset names in cycle order")
    commands.add_parser("status", help="settings and the preset table as json")
    get = commands.add_parser("get", help="print one setting")
    get.add_argument("key", choices=("preset", "nightlight", "brightness"))
    set_ = commands.add_parser("set", help="change one setting and reload the daemon")
    set_.add_argument("key", choices=("preset", "nightlight", "brightness"))
    set_.add_argument("value", help="preset name, on|off, or brightness N|+N|-N percent")
    args = parser.parse_args()
    if args.command == "run":
        return command_run()
    if args.command == "list":
        print("\n".join(PRESETS))
        return 0
    if args.command == "status":
        return command_status()
    if args.command == "get":
        return command_get(args.key)
    assert args.command == "set"
    return command_set(args.key, args.value)


if __name__ == "__main__":
    sys.exit(main())
