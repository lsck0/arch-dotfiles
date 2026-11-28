import QtQuick

PrivacyIndicator {
  label: "Screen shared"
  text: "\u{f1483}"
  devices: videoSources.filter(n => isScreencast(n))
  litByDevice: true
}
