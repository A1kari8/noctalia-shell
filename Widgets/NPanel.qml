import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services

Loader {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  property Component panelContent: null
  property real preferredWidth: 700
  property real preferredHeight: 900
  property real preferredWidthRatio
  property real preferredHeightRatio
  property color panelBackgroundColor: Color.mSurface

  property bool panelAnchorHorizontalCenter: false
  property bool panelAnchorVerticalCenter: false
  property bool panelAnchorTop: false
  property bool panelAnchorBottom: false
  property bool panelAnchorLeft: false
  property bool panelAnchorRight: false

  // Properties to support positioning relative to the opener (button)
  property bool useButtonPosition: false
  property point buttonPosition: Qt.point(0, 0)
  property int buttonWidth: 0
  property int buttonHeight: 0

  property bool panelKeyboardFocus: false
  property bool backgroundClickEnabled: true

  // Animation properties
  readonly property real originalScale: 0.7
  readonly property real originalOpacity: 0.0
  property real scaleValue: originalScale
  property real opacityValue: originalOpacity

  property alias isClosing: hideTimer.running

  signal opened
  signal closed

  active: false
  asynchronous: true

  Component.onCompleted: {
    PanelService.registerPanel(root)
  }

  // -----------------------------------------
  // Functions to control background click behavior
  function disableBackgroundClick() {
    backgroundClickEnabled = false
  }

  function enableBackgroundClick() {
    // Add a small delay to prevent immediate close after drag release
    enableBackgroundClickTimer.restart()
  }

  Timer {
    id: enableBackgroundClickTimer
    interval: 100
    repeat: false
    onTriggered: backgroundClickEnabled = true
  }

  // -----------------------------------------
  function toggle(buttonItem) {
    if (!active || isClosing) {
      open(buttonItem)
    } else {
      close()
    }
  }

  // -----------------------------------------
  function open(buttonItem) {
    // Get the button position if provided
    if (buttonItem !== undefined && buttonItem !== null) {
      useButtonPosition = true

      var itemPos = buttonItem.mapToItem(null, 0, 0)
      buttonPosition = Qt.point(itemPos.x, itemPos.y)
      buttonWidth = buttonItem.width
      buttonHeight = buttonItem.height
    } else {
      useButtonPosition = false
    }

    // Special case if currently closing/animating
    if (isClosing) {
      hideTimer.stop() // in case we were closing
      scaleValue = 1.0
      opacityValue = 1.0
    }

    PanelService.willOpenPanel(root)

    backgroundClickEnabled = true
    active = true
    root.opened()
  }

  // -----------------------------------------
  function close() {
    scaleValue = originalScale
    opacityValue = originalOpacity
    hideTimer.start()
  }

  // -----------------------------------------
  function closeCompleted() {
    root.closed()
    active = false
    useButtonPosition = false
    backgroundClickEnabled = true
    PanelService.closedPanel(root)
  }

  // -----------------------------------------
  // Timer to disable the loader after the close animation is completed
  Timer {
    id: hideTimer
    interval: Style.animationSlow
    repeat: false
    onTriggered: {
      closeCompleted()
    }
  }

  // -----------------------------------------
  sourceComponent: Component {
    PanelWindow {
      id: panelWindow

      // PanelWindow has its own screen property inherited of QsWindow
      property real scaling: ScalingService.getScreenScale(screen)

      readonly property string barPosition: Settings.data.bar.position
      readonly property bool isVertical: barPosition === "left" || barPosition === "right"
      readonly property bool barIsVisible: (screen !== null) && (Settings.data.bar.monitors.includes(screen.name) || (Settings.data.bar.monitors.length === 0))
      readonly property real verticalBarWidth: Math.round(Style.barHeight * scaling)

      Connections {
        target: ScalingService
        function onScaleChanged(screenName, scale) {
          if ((screen !== null) && (screenName === screen.name)) {
            root.scaling = scaling = scale
          }
        }
      }

      Connections {
        target: panelWindow
        function onScreenChanged() {
          root.screen = screen
          root.scaling = scaling = ScalingService.getScreenScale(screen)

          // It's mandatory to force refresh the subloader to ensure the scaling is properly dispatched
          panelContentLoader.active = false
          panelContentLoader.active = true
        }
      }

      visible: true

      // No dimming here
      color: Color.transparent

      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-panel"
      WlrLayershell.keyboardFocus: root.panelKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      Behavior on color {
        ColorAnimation {
          duration: Style.animationNormal
        }
      }

      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true

      margins.top: {
        if (!barIsVisible) {
          return 0
        }
        switch (barPosition || panelAnchorVerticalCenter) {
        case "top":
          return (Style.barHeight + Style.marginS) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * 2 * Style.marginXL * scaling : 0)
        default:
          return Style.marginS * scaling
        }
      }

      margins.bottom: {
        if (!barIsVisible || panelAnchorVerticalCenter) {
          return 0
        }
        switch (barPosition) {
        case "bottom":
          return (Style.barHeight + Style.marginS) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * 2 * Style.marginXL * scaling : 0)
        default:
          return Style.marginS * scaling
        }
      }

      margins.left: {
        if (!barIsVisible || panelAnchorHorizontalCenter) {
          return 0
        }
        switch (barPosition) {
        case "left":
          return (Style.barHeight + Style.marginS) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * 2 * Style.marginXL * scaling : 0)
        default:
          return Style.marginS * scaling
        }
      }

      margins.right: {
        if (!barIsVisible || panelAnchorHorizontalCenter) {
          return 0
        }
        switch (barPosition) {
        case "right":
          return (Style.barHeight + Style.marginS) * scaling + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal * 2 * Style.marginXL * scaling : 0)
        default:
          return Style.marginS * scaling
        }
      }

      // Close any panel with Esc without requiring focus
      Shortcut {
        sequences: ["Escape"]
        enabled: root.active && !root.isClosing
        onActivated: root.close()
        context: Qt.WindowShortcut
      }

      // Clicking outside of the rectangle to close
      MouseArea {
        anchors.fill: parent
        enabled: root.backgroundClickEnabled
        onClicked: root.close()
      }

      Rectangle {
        id: panelBackground
        color: panelBackgroundColor
        radius: Style.radiusL * scaling
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)
        width: {
          var w
          if (preferredWidthRatio !== undefined) {
            w = Math.round(Math.max(screen?.width * preferredWidthRatio, preferredWidth) * scaling)
          } else {
            w = preferredWidth * scaling
          }
          // Clamp width so it is never bigger than the screen
          return Math.min(w, screen?.width - Style.marginL * 2)
        }
        height: {
          var h
          if (preferredHeightRatio !== undefined) {
            h = Math.round(Math.max(screen?.height * preferredHeightRatio, preferredHeight) * scaling)
          } else {
            h = preferredHeight * scaling
          }

          // Clamp width so it is never bigger than the screen
          return Math.min(h, screen?.height - Style.barHeight * scaling - Style.marginL * 2)
        }

        scale: root.scaleValue
        opacity: root.opacityValue

        x: calculatedX
        y: calculatedY

        // ---------------------------------------------
        // ---------------------------------------------
        // All Style.marginXXX are handled above in the PanelWindow itself.
        // Does not account for corners are they are negligible and helps keep the code clean.
        // ---------------------------------------------
        property int calculatedX: {
          // Priority to fixed anchoring
          if (panelAnchorHorizontalCenter) {
            return Math.round((panelWindow.width - panelBackground.width) / 2)
          } else if (panelAnchorLeft) {
            return 0
          } else if (panelAnchorRight) {
            return Math.round(panelWindow.width - panelBackground.width)
          }

          // No fixed anchoring
          if (isVertical) {
            // Vertical bar
            if (barPosition === "right") {
              // To the left of the right bar
              return Math.round(panelWindow.width - panelBackground.width)
            } else {
              // To the right of the left bar
              return 0
            }
          } else {
            // Horizontal bar
            if (root.useButtonPosition) {
              // Position panel relative to button
              var targetX = buttonPosition.x + (buttonWidth / 2) - (panelBackground.width / 2)
              // Keep panel within screen bounds
              var maxX = panelWindow.width - panelBackground.width
              var minX = Style.marginS * scaling
              return Math.round(Math.max(minX, Math.min(targetX, maxX)))
            } else {
              // Fallback to center horizontally
              return Math.round((panelWindow.width - panelBackground.width) / 2)
            }
          }
        }

        // ---------------------------------------------
        property int calculatedY: {
          // Priority to fixed anchoring
          if (panelAnchorVerticalCenter) {
            return Math.round((panelWindow.height - panelBackground.height) / 2)
          } else if (panelAnchorTop) {
            return 0
          } else if (panelAnchorBottom) {
            return Math.round(panelWindow.height - panelBackground.height)
          }

          // No fixed anchoring
          if (isVertical) {
            // Vertical bar
            if (useButtonPosition) {
              // Position panel relative to button
              var targetY = buttonPosition.y + (buttonHeight / 2) - (panelBackground.height / 2)
              // Keep panel within screen bounds
              var maxY = panelWindow.height - panelBackground.height
              var minY = Style.marginS * scaling
              return Math.round(Math.max(minY, Math.min(targetY, maxY)))
            } else {
              // Fallback to center vertically
              return Math.round((panelWindow.height - panelBackground.height) / 2)
            }
          } else {
            // Horizontal bar
            if (barPosition === "bottom") {
              // Above the bottom bar
              return Math.round(panelWindow.height - panelBackground.height)
            } else {
              // Below the top bar
              return 0
            }
          }
        }

        // Animate in when component is completed
        Component.onCompleted: {
          root.scaleValue = 1.0
          root.opacityValue = 1.0
        }

        // Prevent closing when clicking in the panel bg
        MouseArea {
          anchors.fill: parent
        }

        // Animation behaviors
        Behavior on scale {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.OutExpo
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        Loader {
          id: panelContentLoader
          anchors.fill: parent
          sourceComponent: root.panelContent
        }
      }
    }
  }
}
