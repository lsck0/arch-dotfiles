import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "WifiQrModel.js" as WifiQrModel

Item {
  id: root

  property bool opened: false
  property string iface: ""
  property string ssid: ""
  property bool secured: false

  property var qrRows: []
  property int qrSize: 0
  property string error: ""
  property bool loading: false
  property bool expectedStop: false
  property bool pendingShow: false
  property string pendingIface: ""
  property string password: ""
  property bool passwordVisible: false
  property string passwordError: ""
  property bool pwExpectedStop: false

  readonly property bool showingQr: qrSize > 0 && !loading && error === ""

  // text on the overlay card; the code itself keeps its own white quiet zone
  readonly property color onScrim: Color.menu.text
  readonly property color onScrimDim: Util.alpha(Color.menu.text, Style.emphasis.dim)
  readonly property color onScrimUrgent: Color.urgent
  readonly property string fontFamily: Style.font.family

  function open(payload) {
    // the generator's meta line overwrites this ssid
    root.ssid = payload.ssid !== undefined ? String(payload.ssid) : ""
    generate(String(payload.iface || ""))
    root.opened = true
    // window maps after focus: true is evaluated, refocus later
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.pendingShow = false
    if (qrProc.running) {
      root.expectedStop = true
      qrProc.running = false
    }
    if (pwProc.running) {
      root.pwExpectedStop = true
      pwProc.running = false
    }
    root.qrSize = 0
    root.qrRows = []
    root.error = ""
    root.loading = false
    root.iface = ""
    root.ssid = ""
    root.secured = false
    // the password only lives in memory while the card is up
    root.password = ""
    root.passwordVisible = false
    root.passwordError = ""
  }

  function generate(requestedIface) {
    if (qrProc.running) {
      // latest request wins: queue it and stop the old process
      pendingShow = true
      pendingIface = requestedIface
      if (!expectedStop) {
        expectedStop = true
        qrProc.running = false
      }
      return
    }
    qrSize = 0
    qrRows = []
    error = ""
    loading = true
    expectedStop = false
    // a re-summon may share a different connection; drop the old password
    iface = ""
    secured = false
    password = ""
    passwordVisible = false
    passwordError = ""
    if (pwProc.running) {
      pwExpectedStop = true
      pwProc.running = false
    }
    qrProc.command = requestedIface
      ? [Paths.script("network-qr.sh"), "--meta", requestedIface]
      : [Paths.script("network-qr.sh"), "--meta"]
    qrProc.running = true
  }

  function updateQr(raw) {
    var parsed = WifiQrModel.parseQrOutput(raw)
    qrRows = parsed.matrix.rows
    qrSize = parsed.matrix.size
    if (parsed.meta.ssid !== "") ssid = parsed.meta.ssid
    if (parsed.meta.iface !== "") iface = parsed.meta.iface
    secured = parsed.meta.security !== "" && parsed.meta.security !== "nopass"
    // a canceled run's stderr may land late; good output wins
    if (qrSize > 0) error = ""
  }

  function togglePassword() {
    if (passwordVisible) { passwordVisible = false; return }
    if (password !== "") { passwordVisible = true; return }
    if (pwProc.running || !iface) return
    passwordError = ""
    // only a deliberate lookup lowers the canceled-fetch guard
    pwExpectedStop = false
    pwProc.command = [Paths.script("network-password.sh"), iface]
    pwProc.running = true
  }

  Process {
    id: qrProc
    // output buffered after a dismissal must not reopen the card
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedStop) root.updateQr(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedStop) root.error = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.loading = false
      if (root.pendingShow) {
        root.pendingShow = false
        // keep expectedStop set until the replacement launches
        Qt.callLater(function() { root.generate(root.pendingIface) })
        return
      }
      if (root.expectedStop) return
      if (exitCode !== 0 || root.qrSize === 0) {
        root.qrSize = 0
        root.qrRows = []
        if (root.error === "") root.error = "Could not generate the Wi-Fi QR code"
      }
    }
  }

  Process {
    id: pwProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && !root.pwExpectedStop) root.password = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (root.pwExpectedStop) return
      if (!root.opened) return
      if (exitCode === 0 && root.password !== "") root.passwordVisible = true
      else root.passwordError = "Could not read the Wi-Fi password"
    }
  }

  OverlayCard {
    id: panel
    open: root.opened
    name: "network-qr"
    title: root.ssid || "wi-fi"
    hints: [["ESC", "close"]]
    // scanlines would cross the code and hurt the scan
    scanlines: false
    cardWidth: Math.max(content.implicitWidth, Style.space(280)) + chromeWidth
    cardHeight: content.implicitHeight + chromeHeight
    onDismissed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }

    ColumnLayout {
      id: content
      anchors.centerIn: parent
      spacing: Style.spacing.lg

      Rectangle {
        id: qrCanvas
        readonly property int moduleSize: root.qrSize > 0
          ? Math.max(4, Math.floor(Style.space(240) / root.qrSize))
          : 0

        visible: root.showingQr
        width: root.qrSize * moduleSize
        height: width
        color: "white"
        radius: Style.shape.data
        Layout.alignment: Qt.AlignHCenter

        Grid {
          anchors.fill: parent
          columns: root.qrSize

          Repeater {
            model: root.qrSize * root.qrSize

            Rectangle {
              required property int index
              readonly property int matrixRow: Math.floor(index / root.qrSize)
              readonly property int matrixColumn: index % root.qrSize

              width: qrCanvas.moduleSize
              height: qrCanvas.moduleSize
              color: root.qrRows[matrixRow].charAt(matrixColumn) === "1" ? "#111111" : "transparent"
            }
          }
        }
      }

      Text {
        visible: root.loading
        text: ":: GENERATING QR CODE"
        color: root.onScrimDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        textFormat: Text.PlainText
        visible: root.error !== ""
        text: root.error
        color: root.onScrimUrgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(320)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        visible: root.showingQr
        text: ":: SCAN TO JOIN THIS NETWORK"
        color: root.onScrimDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        textFormat: Text.PlainText
        visible: root.showingQr && root.secured
        text: root.passwordError !== "" ? root.passwordError
          : root.passwordVisible ? root.password
          : ":: SHOW PASSWORD"
        color: root.passwordError !== "" ? root.onScrimUrgent : root.onScrim
        opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WrapAnywhere
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(320)
        horizontalAlignment: Text.AlignHCenter

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePassword()
        }
      }
    }
  }
}
