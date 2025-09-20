pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services

Singleton {
  id: root

  // Define our app directories
  // Default config directory: ~/.config/noctalia
  // Default cache directory: ~/.cache/noctalia
  property string shellName: "noctalia"
  property string configDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/"
  property string cacheDir: Quickshell.env("NOCTALIA_CACHE_DIR") || (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/" + shellName + "/"
  property string cacheDirImages: cacheDir + "images/"

  property string settingsFile: Quickshell.env("NOCTALIA_SETTINGS_FILE") || (configDir + "settings.json")

  property string defaultAvatar: Quickshell.env("HOME") + "/.face"
  property string defaultVideosDirectory: Quickshell.env("HOME") + "/Videos"
  property string defaultLocation: "Tokyo"
  property string defaultWallpapersDirectory: Quickshell.env("HOME") + "/Pictures/Wallpapers"
  property string defaultWallpaper: Quickshell.shellDir + "/Assets/Wallpaper/noctalia.png"

  // Used to access via Settings.data.xxx.yyy
  readonly property alias data: adapter

  property bool isLoaded: false
  property bool directoriesCreated: false

  // Signal emitted when settings are loaded after startupcale changes
  signal settingsLoaded

  // -----------------------------------------------------
  // Function to validate monitor configurations
  function validateMonitorConfigurations() {
    var availableScreenNames = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      availableScreenNames.push(Quickshell.screens[i].name)
    }

    Logger.log("Settings", "Available monitors: [" + availableScreenNames.join(", ") + "]")
    Logger.log("Settings", "Configured bar monitors: [" + adapter.bar.monitors.join(", ") + "]")

    // Check bar monitors
    if (adapter.bar.monitors.length > 0) {
      var hasValidBarMonitor = false
      for (var j = 0; j < adapter.bar.monitors.length; j++) {
        if (availableScreenNames.includes(adapter.bar.monitors[j])) {
          hasValidBarMonitor = true
          break
        }
      }
      if (!hasValidBarMonitor) {
        Logger.warn("Settings", "No configured bar monitors found on system, clearing bar monitor list to show on all screens")
        adapter.bar.monitors = []
      } else {

        //Logger.log("Settings", "Found valid bar monitors, keeping configuration")
      }
    } else {

      //Logger.log("Settings", "Bar monitor list is empty, will show on all available screens")
    }
  }

  // -----------------------------------------------------
  // If the settings structure has changed, ensure
  // backward compatibility by upgrading the settings
  function upgradeSettingsData() {

    const sections = ["left", "center", "right"]

    // -----------------
    // 1st. check our settings are not super old, when we only had the widget type as a plain string
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
        var widget = adapter.bar.widgets[sectionName][i]
        if (typeof widget === "string") {
          adapter.bar.widgets[sectionName][i] = {
            "id": widget
          }
        }
      }
    }

    // -----------------
    // 2nd. remove any non existing widget type
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      const widgets = adapter.bar.widgets[sectionName]
      // Iterate backward through the widgets array, so it does not break when removing a widget
      for (var i = widgets.length - 1; i >= 0; i--) {
        var widget = widgets[i]
        if (!BarWidgetRegistry.hasWidget(widget.id)) {
          widgets.splice(i, 1)
          Logger.warn(`Settings`, `Deleted invalid widget ${widget.id}`)
        }
      }
    }

    // -----------------
    // 3nd. migrate global settings to user settings
    for (var s = 0; s < sections.length; s++) {
      const sectionName = sections[s]
      for (var i = 0; i < adapter.bar.widgets[sectionName].length; i++) {
        var widget = adapter.bar.widgets[sectionName][i]

        // Check if widget registry supports user settings, if it does not, then there is nothing to do
        const reg = BarWidgetRegistry.widgetMetadata[widget.id]
        if ((reg === undefined) || (reg.allowUserSettings === undefined) || !reg.allowUserSettings) {
          continue
        }

        if (upgradeWidget(widget)) {
          Logger.log("Settings", `Upgraded ${widget.id} widget:`, JSON.stringify(widget))
        }
      }
    }

    // Upgrade the density of the bar so the look stay the same for people who upgrade.
    // TODO: remove soon
    if (adapter.settingsVersion == 2) {
      adapter.bar.density = "comfortable"
      adapter.settingsVersion++
    }
  }

  // -----------------------------------------------------
  function upgradeWidget(widget) {
    // Backup the widget definition before altering
    const widgetBefore = JSON.stringify(widget)

    switch (widget.id) {
      // Get back to global settings for these two clock settings
    case "Clock":
      if (widget.use12HourClock !== undefined) {
        adapter.location.use12hourFormat = widget.use12HourClock
        delete widget.use12HourClock
      }
      break
    }

    // Get all existing custom settings keys
    const keys = Object.keys(BarWidgetRegistry.widgetMetadata[widget.id])

    // Delete deprecated user settings from the wiget
    for (const k of Object.keys(widget)) {
      if (k === "id" || k === "allowUserSettings") {
        continue
      }
      if (!keys.includes(k)) {
        delete widget[k]
      }
    }

    // Inject missing default setting (metaData) from BarWidgetRegistry
    for (var i = 0; i < keys.length; i++) {
      const k = keys[i]
      if (k === "id" || k === "allowUserSettings") {
        continue
      }

      if (widget[k] === undefined) {
        widget[k] = BarWidgetRegistry.widgetMetadata[widget.id][k]
      }
    }

    // Compare settings, to detect if something has been upgraded
    const widgetAfter = JSON.stringify(widget)
    return (widgetAfter !== widgetBefore)
  }
  // -----------------------------------------------------
  // Kickoff essential services
  function kickOffServices() {
    // Ensure our location singleton is created as soon as possible so we start fetching weather asap
    LocationService.init()

    NightLightService.apply()

    ColorSchemeService.init()

    MatugenService.init()

    // Ensure wallpapers are restored after settings have been loaded
    WallpaperService.init()

    FontService.init()

    HooksService.init()

    BluetoothService.init()
  }

  // -----------------------------------------------------
  // Ensure directories exist before FileView tries to read files
  Component.onCompleted: {
    // ensure settings dir exists
    Quickshell.execDetached(["mkdir", "-p", configDir])
    Quickshell.execDetached(["mkdir", "-p", cacheDir])
    Quickshell.execDetached(["mkdir", "-p", cacheDirImages])

    // Mark directories as created and trigger file loading
    directoriesCreated = true
  }

  // Don't write settings to disk immediately
  // This avoid excessive IO when a variable changes rapidly (ex: sliders)
  Timer {
    id: saveTimer
    running: false
    interval: 1000
    onTriggered: settingsFileView.writeAdapter()
  }

  FileView {
    id: settingsFileView
    path: directoriesCreated ? settingsFile : undefined
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: saveTimer.start()

    // Trigger initial load when path changes from empty to actual path
    onPathChanged: {
      if (path !== undefined) {
        reload()
      }
    }
    onLoaded: function () {
      if (!isLoaded) {
        Logger.log("Settings", "----------------------------")
        Logger.log("Settings", "Settings loaded successfully")

        upgradeSettingsData()

        validateMonitorConfigurations()

        kickOffServices()

        isLoaded = true

        // Emit the signal
        root.settingsLoaded()
      }
    }
    onLoadFailed: function (error) {
      if (error.toString().includes("No such file") || error === 2)
        // File doesn't exist, create it with default values
        writeAdapter()
    }

    JsonAdapter {
      id: adapter

      property int settingsVersion: 3

      // bar
      property JsonObject bar: JsonObject {
        property string position: "top" // "top", "bottom", "left", or "right"
        property real backgroundOpacity: 1.0
        property list<string> monitors: []
        property string density: "default" // "compact", "default", "comfortable"
        property bool showCapsule: true

        // Floating bar settings
        property bool floating: false
        property real marginVertical: 0.25
        property real marginHorizontal: 0.25

        // Widget configuration for modular bar system
        property JsonObject widgets
        widgets: JsonObject {
          property list<var> left: [{
              "id": "SystemMonitor"
            }, {
              "id": "ActiveWindow"
            }, {
              "id": "MediaMini"
            }]
          property list<var> center: [{
              "id": "Workspace"
            }]
          property list<var> right: [{
              "id": "ScreenRecorderIndicator"
            }, {
              "id": "Tray"
            }, {
              "id": "NotificationHistory"
            }, {
              "id": "WiFi"
            }, {
              "id": "Bluetooth"
            }, {
              "id": "Battery"
            }, {
              "id": "Volume"
            }, {
              "id": "Brightness"
            }, {
              "id": "NightLight"
            }, {
              "id": "Clock"
            }, {
              "id": "SidePanelToggle"
            }]
        }
      }

      // general
      property JsonObject general: JsonObject {
        property string avatarImage: defaultAvatar
        property bool dimDesktop: true
        property bool showScreenCorners: false
        property bool forceBlackScreenCorners: false
        property real radiusRatio: 1.0
        property real screenRadiusRatio: 1.0
        property real animationSpeed: 1.0
      }

      // location
      property JsonObject location: JsonObject {
        property string name: defaultLocation
        property bool useFahrenheit: false
        property bool use12hourFormat: false
        property bool showWeekNumberInCalendar: false
      }

      // screen recorder
      property JsonObject screenRecorder: JsonObject {
        property string directory: defaultVideosDirectory
        property int frameRate: 60
        property string audioCodec: "opus"
        property string videoCodec: "h264"
        property string quality: "very_high"
        property string colorRange: "limited"
        property bool showCursor: true
        property string audioSource: "default_output"
        property string videoSource: "portal"
      }

      // wallpaper
      property JsonObject wallpaper: JsonObject {
        property bool enabled: true
        property string directory: defaultWallpapersDirectory
        property bool enableMultiMonitorDirectories: false
        property bool setWallpaperOnAllMonitors: true
        property string fillMode: "crop"
        property color fillColor: "#000000"
        property bool randomEnabled: false
        property int randomIntervalSec: 300 // 5 min
        property int transitionDuration: 1500 // 1500 ms
        property string transitionType: "random"
        property real transitionEdgeSmoothness: 0.05
        property list<var> monitors: []
      }

      // applauncher
      property JsonObject appLauncher: JsonObject {
        property bool enableClipboardHistory: false
        // Position: center, top_left, top_right, bottom_left, bottom_right, bottom_center, top_center
        property string position: "center"
        property real backgroundOpacity: 1.0
        property list<string> pinnedExecs: []
        property bool useApp2Unit: false
        property bool sortByMostUsed: true
      }

      // dock
      property JsonObject dock: JsonObject {
        property bool autoHide: false
        property bool exclusive: false
        property real backgroundOpacity: 1.0
        property real floatingRatio: 1.0
        property list<string> monitors: []
      }

      // network
      property JsonObject network: JsonObject {
        property bool wifiEnabled: true
        property bool bluetoothEnabled: true
      }

      // notifications
      property JsonObject notifications: JsonObject {
        property bool doNotDisturb: false
        property list<string> monitors: []
        // Last time the user opened the notification history (ms since e899999999999998poch)
        property real lastSeenTs: 0
        // Duration settings for different urgency levels (in seconds)
        property int lowUrgencyDuration: 3
        property int normalUrgencyDuration: 8
        property int criticalUrgencyDuration: 15
      }

      // audio
      property JsonObject audio: JsonObject {
        property int volumeStep: 5
        property int cavaFrameRate: 60
        property string visualizerType: "linear"
        property list<string> mprisBlacklist: []
        property string preferredPlayer: ""
      }

      // ui
      property JsonObject ui: JsonObject {
        property string fontDefault: "Roboto"
        property string fontFixed: "DejaVu Sans Mono"
        property string fontBillboard: "Inter"
        property list<var> monitorsScaling: []
        property bool idleInhibitorEnabled: false
      }

      // brightness
      property JsonObject brightness: JsonObject {
        property int brightnessStep: 5
      }

      property JsonObject colorSchemes: JsonObject {
        property bool useWallpaperColors: false
        property string predefinedScheme: ""
        property bool darkMode: true
      }

      // matugen templates toggles
      property JsonObject matugen: JsonObject {
        // Per-template flags to control dynamic config generation
        property bool gtk4: false
        property bool gtk3: false
        property bool qt6: false
        property bool qt5: false
        property bool kitty: false
        property bool ghostty: false
        property bool foot: false
        property bool fuzzel: false
        property bool vesktop: false
        property bool pywalfox: false
        property bool enableUserTemplates: false
      }

      // night light
      property JsonObject nightLight: JsonObject {
        property bool enabled: false
        property bool forced: false
        property bool autoSchedule: true
        property string nightTemp: "4000"
        property string dayTemp: "6500"
        property string manualSunrise: "06:30"
        property string manualSunset: "18:30"
      }

      // hooks
      property JsonObject hooks: JsonObject {
        property bool enabled: false
        property string wallpaperChange: ""
        property string darkModeChange: ""
      }
    }
  }
}
