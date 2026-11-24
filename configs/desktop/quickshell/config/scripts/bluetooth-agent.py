#!/usr/bin/env python3
# BlueZ pairing agent for the shell (Commons/BluetoothAgent.qml). Registers org.bluez.Agent1 as the default agent and
# speaks JSON lines: each request bluez sends goes to stdout as {id, type, device, name, passkey}, and the shell answers
# on stdin with {id, accept, value}. Display requests (display-passkey, display-pin) take no answer; cancel withdraws
# the open request. nushell cannot serve a D-Bus object, hence python with gio.

import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

try:
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix  # noqa: E402

    UnixInputStream = GioUnix.InputStream
except ValueError, ImportError:
    UnixInputStream = Gio.UnixInputStream

AGENT_PATH = "/dev/lsck0/quickshell/bluetooth_agent"
CAPABILITY = "KeyboardDisplay"

INTROSPECTION = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey">
      <arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/>
    </method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
# id -> (invocation, method): the requests the shell has not answered yet
pending = {}
next_id = 0


def emit(record):
    sys.stdout.write(json.dumps(record) + "\n")
    sys.stdout.flush()


def device_name(path):
    try:
        reply = bus.call_sync(
            "org.bluez",
            path,
            "org.freedesktop.DBus.Properties",
            "Get",
            GLib.Variant("(ss)", ("org.bluez.Device1", "Alias")),
            GLib.VariantType("(v)"),
            Gio.DBusCallFlags.NONE,
            2000,
            None,
        )
        return reply.unpack()[0]
    except GLib.Error:
        return path.rsplit("/", 1)[-1].removeprefix("dev_").replace("_", ":")


def reject(invocation, reason="Rejected"):
    invocation.return_dbus_error("org.bluez.Error." + reason, reason)


def request(kind, device, invocation=None, passkey=""):
    global next_id
    next_id += 1
    if invocation is not None:
        pending[next_id] = (invocation, kind)
    emit({"id": next_id, "type": kind, "device": device, "name": device_name(device), "passkey": passkey})


def on_call(_conn, _sender, _path, _iface, method, params, invocation):
    args = params.unpack()
    if method == "Release":
        invocation.return_value(None)
    elif method == "Cancel":
        for invoc, _ in pending.values():
            reject(invoc, "Canceled")
        pending.clear()
        emit({"type": "cancel"})
        invocation.return_value(None)
    elif method == "RequestPinCode":
        request("pin", args[0], invocation)
    elif method == "RequestPasskey":
        request("passkey", args[0], invocation)
    elif method == "RequestConfirmation":
        request("confirm", args[0], invocation, "%06d" % args[1])
    elif method == "RequestAuthorization":
        request("authorize", args[0], invocation)
    elif method == "AuthorizeService":
        request("service", args[0], invocation, args[1])
    elif method == "DisplayPinCode":
        request("display-pin", args[0], None, args[1])
        invocation.return_value(None)
    elif method == "DisplayPasskey":
        request("display-passkey", args[0], None, "%06d" % args[1])
        invocation.return_value(None)
    else:
        reject(invocation)


def answer(line):
    try:
        reply = json.loads(line)
        invocation, kind = pending.pop(int(reply["id"]))
    except ValueError, KeyError, TypeError:
        return
    if not reply.get("accept"):
        reject(invocation)
    elif kind == "pin":
        invocation.return_value(GLib.Variant("(s)", (str(reply.get("value", "")),)))
    elif kind == "passkey":
        try:
            invocation.return_value(GLib.Variant("(u)", (int(reply.get("value", "")),)))
        except ValueError:
            reject(invocation)
    else:
        invocation.return_value(None)


def on_stdin(stream, result):
    line, _ = stream.read_line_finish_utf8(result)
    if line is None:  # the shell closed the pipe: quit, bluez drops the agent with the bus name
        loop.quit()
        return
    answer(line)
    stream.read_line_async(GLib.PRIORITY_DEFAULT, None, on_stdin)


def register():
    manager = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None, "org.bluez", "/org/bluez", "org.bluez.AgentManager1", None
    )
    manager.call_sync("RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, CAPABILITY)), Gio.DBusCallFlags.NONE, -1, None)
    manager.call_sync("RequestDefaultAgent", GLib.Variant("(o)", (AGENT_PATH,)), Gio.DBusCallFlags.NONE, -1, None)


node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
bus.register_object(AGENT_PATH, node.interfaces[0], on_call, None, None)
# bluetoothd not running (no adapter): exit non-zero, the shell retries later
register()
emit({"type": "ready"})

stdin = Gio.DataInputStream.new(UnixInputStream.new(sys.stdin.fileno(), False))
stdin.read_line_async(GLib.PRIORITY_DEFAULT, None, on_stdin)
loop = GLib.MainLoop()
loop.run()
