.pragma library

// loaded once at start; `quickshell ipc call shell summon <id> [json]` hands the parsed payload to open()
const shell = {
    "panel.alert":           "alert/Alert.qml",
    "panel.disk-speedtest":  "disk-speedtest/Panel.qml",
    "panel.image-picker":    "image-picker/ImagePicker.qml",
    "panel.reminders":       "reminders/ReminderFlow.qml",
    "panel.speedtest":       "speedtest/Panel.qml",
    "panel.wifiqr":          "wifiqr/Panel.qml",
    "service.notifications": "notifications/Service.qml"
};

// bar widgets by file name in bar/widgets, the rest of that dir is unplaced
const bar = {
    left:   ["AppMenu", "Workspaces"],
    center: ["Clock", "Weather", "Media", "Obs", "Discord"],
    right:  ["Tray", "Separator", "Agents", "Homelab", "System", "Network", "Display", "AudioIO", "Notifications",
             "KeyboardLayout", "Indicators", "Exit"]
};

// non-main screens
const barSecondary = { left: ["AppMenu", "Workspaces"], center: [], right: [] };
