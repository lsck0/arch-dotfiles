.pragma library

const shell = {
    "panel.alert":           "alert/Alert.qml",
    "panel.image-picker":    "image-picker/ImagePicker.qml",
    "panel.reminders":       "reminders/ReminderFlow.qml",
    "panel.speedtest":       "speedtest/Panel.qml",
    "panel.tasks":           "tasks/Tasks.qml",
    "panel.wifiqr":          "wifiqr/Panel.qml",
    "service.notifications": "notifications/Service.qml"
};

const bar = {
    left:   ["AppMenu", "Workspaces"],
    center: ["Clock", "Weather", "Media", "Obs", "Discord"],
    right:  ["Tray", "Separator", "Agents", "Homelab", "System", "Network",
             "Display", "AudioIO", "Notifications", "KeyboardLayout", "Indicators", "Exit"]
};

const barSecondary = { left: ["AppMenu", "Workspaces"], center: [], right: [] };
