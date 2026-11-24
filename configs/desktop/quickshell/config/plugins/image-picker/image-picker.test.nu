#!/usr/bin/env -S nu --no-config-file
# ImagePickerModel.js under qmltestrunner: the scan's rows, the filter and the recent tiles

use ../../scripts/lib/qml-test.nu [qml-test-run]

const MODEL = path self ImagePickerModel.js
const TEST = '
import QtQuick
import QtTest
import "ImagePickerModel.js" as Model

TestCase {
  name: "image-picker"

  // five by Ann, two artists with one each, in the scan order list.nu prints
  readonly property var images: Model.loadRows(["ann-a", "ann-b", "ann-c", "ann-d", "ann-e", "bo-night-sea", "cy-x"]
    .map(function(name) { return "/w/" + name + ".jpg\t/t/" + name + ".jpg\t\t" + { ann: "Ann Lee", bo: "Bo", cy: "Cy" }[name.split("-")[0]] }).join("\n"))

  function test_rows() {
    compare(images.length, 7)
    compare(images[0].artist, "Ann Lee")
    compare(Model.pickFor(images[0]), "/w/ann-a.jpg")
    compare(Model.pickFor(Model.loadRows("/w/x.jpg\t/t/x.jpg\tnord\tBo")[0]), "nord")
    compare(Model.loadRows("/a/x.jpg\n/b/x.jpg\n\n").length, 1)
    compare(Model.indexOfPick(images, "/w/bo-night-sea.jpg"), 5)
    compare(Model.indexOfPick(images, ""), 0)
  }

  function test_filter_words_in_any_order() {
    verify(Model.matches(images[5], ["sea", "bo"]))
    verify(Model.matches(images[0], ["lee", "ann"]))
    verify(!Model.matches(images[5], ["sea", "ann"]))
  }

  function test_recent_tiles() {
    const recent = Model.loadRecent(["theme\tnord\t/t/n.jpg\t{\"special\":{}}", "theme\tvoid\t/t/v.jpg\tbroken", "theme\ta\t/t/a.jpg\t",
      "theme\tb\t/t/b.jpg\t", "theme\tc\t/t/c.jpg\t", "wallpaper\t/w/ann-lee-sea.jpg\t/t/s.jpg\t"].join("\n"))
    compare(recent[0].label, "Nord")
    verify(recent[0].palette !== null)
    compare(recent[1].palette, null)
    compare(recent[5].label, "Ann Lee Sea")
    const tiles = Model.recentTiles(recent, ["/w/other.jpg", "void"], 3)
    compare(tiles.map(function(tile) { return tile.pick }), ["/w/ann-lee-sea.jpg", "nord", "a", "b"])
    compare(tiles.map(function(tile) { return tile.slot }), [0, 1, 2, 3])
    compare(Model.recentTiles(recent, ["/w/ann-lee-sea.jpg", ""], 3).length, 3)
    compare(Model.recentTiles([], ["", ""], 3).length, 0)
  }
}
'

def main [] {
    qml-test-run $TEST {|dir| cp $MODEL $dir }
}
