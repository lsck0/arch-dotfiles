pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Removable and hot-pluggable drives through udisks2: hidden while none is plugged in. drives.nu lists them from
// lsblk and acts through udisksctl; `udisksctl monitor` drives the refresh.
BarWidget {
  id: root

  moduleName: "drives"
  barPriority: 30
  hoverPanel: true
  hoverFill: true
  hoverCursor: Qt.ArrowCursor

  // drives.nu list: [{path, name, sizeBytes, transport, canPowerOff, volumes: [{path, name, label, fstype, sizeBytes,
  // mountpoint, usedBytes, fsSizeBytes, locked, readOnly}]}]; a failed refresh keeps the last list
  property var drives: []
  property string listError: ""
  property real listUpdatedMs: 0

  // one udisks action at a time; its failure stays beside the volume or drive it was for until that one succeeds
  property string actionDevice: ""
  readonly property string busyDevice: actionProc.running ? actionDevice : ""
  property var actionErrors: ({})
  function actionError(device) { return actionErrors[device] || "" }

  visible: drives.length > 0
  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2

  function refresh() { listProc.run() }

  // drives.nu mount|unmount <volume>, eject <drive>
  function act(verb, device) {
    if (actionProc.running) return
    actionDevice = device
    actionErrors = Util.mapWithout(actionErrors, device)
    actionProc.command = [Paths.barWidget("drives.nu"), verb, device]
    actionProc.running = true
  }

  function openInFileManager(mountpoint) {
    closePanel()
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", mountpoint])
  }

  function volumeTitle(volume) { return volume.label !== "" ? volume.label : volume.name }
  function volumeUsage(volume) {
    if (volume.mountpoint === "" || !volume.fsSizeBytes) return Util.bytes(volume.sizeBytes)
    return Util.bytesOf(volume.usedBytes, volume.fsSizeBytes) + " :: " + Math.round(volume.usedBytes / volume.fsSizeBytes * 100) + "%"
  }
  function volumeNote(volume) {
    if (volume.locked) return "locked"
    return volume.fstype + (volume.readOnly ? " :: ro" : "")
  }

  JsonProcess {
    id: listProc
    command: [Paths.barWidget("drives.nu"), "list"]
    onParsed: function (data) {
      if (!Util.isList(data)) {
        root.listError = "bad json"
        return
      }
      root.drives = data
      root.listError = ""
      root.listUpdatedMs = Date.now()
    }
    onFailed: root.listError = "bad json"
  }
  Component.onCompleted: refresh()

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function (exitCode) {
      let device = root.actionDevice
      if (exitCode !== 0) {
        let text = actionStderr.text.trim()
        root.actionErrors = Util.mapSet(root.actionErrors, device, text !== "" ? text : "failed (" + exitCode + ")")
      }
      root.refresh()
    }
  }

  EventWatcher {
    command: ["udisksctl", "monitor"]
    onFired: root.refresh()
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{f129a}"
      color: Colors.bar.text
      icon: true
      font.pixelSize: Style.font.icon
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.drives.length > 1
      text: String(root.drives.length)
      color: Colors.bar.text
      caption: true
    }
    DataState {
      anchors.verticalCenter: parent.verticalCenter
      loading: listProc.running
      error: root.listError
      updatedMs: root.listUpdatedMs
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    // usage moves while files copy, which udisks does not report
    onOpened: root.refresh()
    title: "DRIVES"
    implicitWidth: Style.panelWidth.normal

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: root.drives
        delegate: Column {
          id: drive
          required property var modelData
          required property int index
          width: content.width
          spacing: Style.spacing.xs

          PanelSeparator { visible: drive.index > 0 }
          PanelSectionHeader {
            // the device picks its model name: plain text
            width: parent.width
            elide: Text.ElideRight
            text: drive.modelData.name + " :: " + Util.bytes(drive.modelData.sizeBytes)
              + (drive.modelData.transport !== "" ? " :: " + drive.modelData.transport : "")
          }

          Repeater {
            model: drive.modelData.volumes
            delegate: Column {
              id: volume
              required property var modelData
              readonly property bool mounted: modelData.mountpoint !== ""
              readonly property bool busy: root.busyDevice === modelData.path
              width: drive.width
              spacing: Style.spacing.xxs
              opacity: busy ? Style.emphasis.dim : 1

              StatRow {
                label: root.volumeTitle(volume.modelData)
                value: root.volumeUsage(volume.modelData)
                note: root.volumeNote(volume.modelData)
              }
              StatRow {
                visible: volume.mounted
                label: "Open"
                value: volume.modelData.mountpoint
                valueElide: Text.ElideLeft
                clickable: true
                onActivated: root.openInFileManager(volume.modelData.mountpoint)
              }
              Button {
                visible: !volume.modelData.locked
                variant: "action"
                focusable: true
                enabled: !actionProc.running
                text: volume.busy ? (volume.mounted ? "Unmounting" : "Mounting") : (volume.mounted ? "Unmount" : "Mount")
                onClicked: root.act(volume.mounted ? "unmount" : "mount", volume.modelData.path)
              }
              Label {
                visible: root.actionError(volume.modelData.path) !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: root.actionError(volume.modelData.path)
                color: Colors.urgentText
                caption: true
              }
            }
          }

          Label {
            visible: drive.modelData.volumes.length === 0
            text: "> NO FILESYSTEM"
            dim: true
            caption: true
          }

          Button {
            visible: drive.modelData.canPowerOff
            variant: "action"
            focusable: true
            enabled: !actionProc.running
            text: root.busyDevice === drive.modelData.path ? "Ejecting" : "Eject"
            onClicked: root.act("eject", drive.modelData.path)
          }
          Label {
            visible: root.actionError(drive.modelData.path) !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.actionError(drive.modelData.path)
            color: Colors.urgentText
            caption: true
          }
        }
      }
    }
  }
}
