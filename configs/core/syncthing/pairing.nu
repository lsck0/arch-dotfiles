# What a pairing is in a syncthing config.xml: its devices with their addresses and its folders with their members.
export def pairing-read []: string -> record {
    let nodes = $in | from xml | get content
    let children = {|node: record, tag: string| $node.content | where tag == $tag }
    {
        devices: ($nodes | where tag == device | each {|device|
            {
                id: $device.attributes.id
                name: ($device.attributes.name? | default "")
                addresses: (do $children $device address | each {|address| $address.content.0.content } | sort)
            }
        } | sort-by id)
        folders: ($nodes | where tag == folder | each {|folder|
            {id: $folder.attributes.id, path: $folder.attributes.path, devices: (do $children $folder device | each { $in.attributes.id } | sort)}
        } | sort-by id)
    }
}
