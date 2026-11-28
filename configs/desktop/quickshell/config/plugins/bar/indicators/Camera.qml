import QtQuick

PrivacyIndicator {
  label: "Camera"
  text: "\u{f05a0}"
  devices: videoSources.filter(n => !isScreencast(n))
}
