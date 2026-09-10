import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SessionModel.js" as Model

Panel {
  id: root
  moduleName: "blr.den"
  ipcTarget: "blr.den"
  manageIpc: false

  readonly property string backendPath: Qt.resolvedUrl("collie.py").toString().replace("file://", "")
  readonly property string bridgeUrl: String(setting("bridgeUrl", "http://127.0.0.1:8787"))
  readonly property string browserUrl: String(setting("browserUrl", bridgeUrl))
  readonly property color foreground: Color.popups.text
  readonly property color muted: alpha(foreground, 0.65)
  readonly property color line: alpha(foreground, 0.11)
  readonly property color ready: "#45c881"
  readonly property color working: "#dda34b"
  readonly property color urgent: "#f16e79"
  readonly property string fontFamily: Style.font.family
  readonly property int rowHeight: Math.max(Style.space(34), Style.font.bodySmall + Style.font.caption + Style.space(10))
  readonly property int headingHeight: Style.space(23)
  readonly property string navigationTarget: String(setting("navigationTarget", "Collie dashboard"))
  readonly property bool opensHerdr: navigationTarget === "Herdr terminal"
  readonly property int openRefreshMs: Math.max(1000, Number(setting("openRefreshSeconds", 2)) * 1000)
  readonly property int closedRefreshMs: Math.max(5000, Number(setting("closedRefreshSeconds", 10)) * 1000)
  readonly property bool motionEnabled: !Boolean(setting("reduceMotion", false))
  readonly property int quickMotion: motionEnabled ? 110 : 0
  readonly property int gentleMotion: motionEnabled ? 160 : 0
  readonly property string category: view === "detail" && breadcrumbs.length ? (breadcrumbs[0].kind === "tab" ? "tabs" : "spaces") : view

  property var snapshot: ({})
  property string errorText: ""
  property string actionError: ""
  property bool refreshing: false
  property bool hasSnapshot: false
  property string selectedSession: ""
  property string view: "agents"
  property var breadcrumbs: []
  property string query: ""
  property bool recentOpen: Boolean(setting("recentOpen", true))
  property bool recentNewest: Boolean(setting("recentNewest", true))
  property string selectedKey: ""
  property string feedbackText: ""
  property double now: Date.now()

  readonly property bool connected: hasSnapshot && snapshot.bridge === "connected" && errorText === ""
  readonly property var agents: Model.items(snapshot, "agents")
  readonly property var spaces: Model.items(snapshot, "workspaces")
  readonly property var tabs: Model.items(snapshot, "tabs")
  readonly property var shells: Model.items(snapshot, "shellPanes")
  readonly property var sessions: Model.items(snapshot, "sessions")
  readonly property string activeSession: selectedSession || (sessions.find(function(s) { return s.isPrimary }) || sessions[0] || {name: "default"}).name
  readonly property int blockedCount: agents.filter(function(a) { return Model.bucket(a) === "needs" }).length
  readonly property int readyCount: agents.filter(function(a) { return Model.bucket(a) === "ready" }).length
  readonly property int workingCount: agents.filter(function(a) { return Model.bucket(a) === "working" }).length
  readonly property var scope: breadcrumbs.length ? breadcrumbs[breadcrumbs.length - 1] : null
  readonly property var rows: Model.build(snapshot, view, query, scope, recentOpen, recentNewest)
  readonly property int resultCount: rows.filter(function(r) { return r.kind !== "heading" }).length
  readonly property real rowsHeight: rows.reduce(function(total, r) { return total + (r.kind === "heading" ? root.headingHeight : root.rowHeight) }, 0)
  readonly property real unfilteredRowsHeight: query ? Model.build(snapshot, view, "", scope, recentOpen, recentNewest).reduce(function(total, r) { return total + (r.kind === "heading" ? root.headingHeight : root.rowHeight) }, 0) : rowsHeight
  readonly property var categories: [
    {key: "agents", title: "Agents"},
    {key: "spaces", title: "Spaces"},
    {key: "tabs", title: "Tabs"},
    {key: "shells", title: "Shells"}
  ]

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
  function tone(score) { return score === 4 ? urgent : score === 3 ? ready : score === 2 ? working : muted }
  function elapsed(stamp) {
    if (!stamp) return ""
    var minutes = Math.max(0, Math.floor((now - stamp) / 60000))
    return minutes < 1 ? "now" : minutes < 60 ? minutes + "m" : minutes < 1440 ? Math.floor(minutes / 60) + "h" : Math.floor(minutes / 1440) + "d"
  }
  function saveSetting(key, value) {
    var entry = Object.assign({}, settings, {id: moduleName})
    entry[key] = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function") bar.shell.updateEntryInline(moduleName, entry)
  }
  function setView(next) {
    if (next !== view || breadcrumbs.length) animateNavigation(categories.findIndex(function(c) { return c.key === next }) >= categories.findIndex(function(c) { return c.key === category }) ? 1 : -1)
    itemMenu.close()
    view = next
    breadcrumbs = []
    query = ""
    selectedKey = ""
    list.positionViewAtBeginning()
  }
  function browse(row) {
    if (!row || !row.canBrowse) return
    animateNavigation(1)
    itemMenu.close()
    breadcrumbs = breadcrumbs.concat([row])
    view = "detail"
    query = ""
    selectedKey = ""
    list.positionViewAtBeginning()
  }
  function back() {
    if (!breadcrumbs.length) return
    animateNavigation(-1)
    itemMenu.close()
    var previous = breadcrumbs[0].kind === "tab" ? "tabs" : "spaces"
    breadcrumbs = breadcrumbs.slice(0, -1)
    view = breadcrumbs.length ? "detail" : previous
    query = ""
    selectedKey = ""
  }
  function selectSession(name) {
    if (name === activeSession) return
    itemMenu.close()
    selectedSession = name
    snapshot = {sessions: sessions}
    hasSnapshot = false
    errorText = ""
    actionError = ""
    setView("agents")
    fetch()
  }
  function nextSession() {
    if (sessions.length < 2) return
    var i = sessions.findIndex(function(s) { return s.name === activeSession })
    selectSession(sessions[(i + 1) % sessions.length].name)
  }
  function animateNavigation(direction) {
    navigationMotion.stop()
    list.opacity = motionEnabled && opened ? 0.78 : 1
    listShift.x = motionEnabled && opened ? Style.space(4) * direction : 0
    if (motionEnabled && opened) navigationMotion.start()
  }
  function refreshNow() {
    if (refreshing) return
    if (motionEnabled) refreshSpin.restart()
    fetch()
  }
  function fetch() {
    if (refreshing || itemMenu.visible || sessionMenu.visible) return
    refreshing = true
    fetchProc.session = selectedSession
    fetchProc.command = ["python3", "-B", backendPath, "snapshot", bridgeUrl, selectedSession]
    fetchProc.running = true
  }
  function openWeb(row) {
    if (launchProc.running || focusProc.running) return
    actionError = ""
    launchProc.command = ["xdg-open", Model.webUrl(snapshot, browserUrl, selectedSession, row)]
    launchProc.running = true
  }
  function activate(row, target) {
    if (!row || focusProc.running || launchProc.running) return
    if (row.kind === "heading") {
      if (row.collapsible) saveSetting("recentOpen", !recentOpen)
      return
    }
    var useHerdr = target ? target === "Herdr terminal" : opensHerdr
    if (!useHerdr || row.item.host) { openWeb(row); return }
    actionError = ""
    var id = row.kind === "pane" ? row.item.paneId : row.kind === "tab" ? row.item.tabId : row.item.workspaceId
    var action = row.kind === "pane" ? "focus-pane" : row.kind === "tab" ? "focus-tab" : "focus-workspace"
    focusProc.command = ["python3", "-B", backendPath, action, bridgeUrl, selectedSession, String(id)]
    focusProc.running = true
  }
  function showItemMenu(row, anchor, x, y) {
    if (!row || row.kind === "heading" || focusProc.running || launchProc.running) return
    selectedKey = row.key
    itemMenu.row = row
    itemMenu.link = Model.webUrl(snapshot, browserUrl, selectedSession, row)
    var position = anchor.mapToItem(content, x, y)
    itemMenu.popup(position.x, position.y)
  }
  function showSelectedMenu() {
    var row = selectedRow()
    if (!row) { moveSelection(1); row = selectedRow() }
    if (!row) return
    var index = rows.findIndex(function(r) { return r.key === row.key })
    list.positionViewAtIndex(index, ListView.Contain)
    var delegate = list.itemAtIndex(index)
    showItemMenu(row, delegate || list, Style.space(24), delegate ? delegate.height : Style.space(24))
  }
  function copyDetail(value, label) {
    Quickshell.clipboardText = String(value)
    feedbackText = "Copied " + label
    feedbackTimer.restart()
  }
  function browseWorkspace(row) {
    var workspace = Model.workspace(snapshot, row.item)
    if (!workspace) return
    setView("spaces")
    browse(Model.row(snapshot, workspace, "space"))
  }
  function selectedRow() { return rows.find(function(r) { return r.key === selectedKey }) }
  function moveSelection(direction) {
    if (!rows.length) return
    var i = rows.findIndex(function(r) { return r.key === selectedKey })
    if (i < 0) i = direction > 0 ? -1 : rows.length
    do { i += direction } while (i >= 0 && i < rows.length && rows[i].kind === "heading")
    if (i < 0 || i >= rows.length) return
    selectedKey = rows[i].key
    list.positionViewAtIndex(i, ListView.Contain)
  }
  function destination(row) { return opensHerdr && !(row && row.item && row.item.host) ? "Herdr" : "Collie" }
  function handleKey(event) {
    if (itemMenu.visible || sessionMenu.visible) return
    var control = event.modifiers & Qt.ControlModifier
    if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) showSelectedMenu()
    else if (event.key === Qt.Key_Escape) {
      if (query) { query = ""; search.forceActiveFocus() }
      else if (breadcrumbs.length) back()
      else close()
    } else if (control && event.key === Qt.Key_F) { search.forceActiveFocus(); search.selectAll() }
    else if (control && event.key === Qt.Key_R) refreshNow()
    else if (control && event.key === Qt.Key_O) openWeb(null)
    else if (control && event.key === Qt.Key_D) saveSetting("navigationTarget", opensHerdr ? "Collie dashboard" : "Herdr terminal")
    else if (control && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) setView(categories[event.key - Qt.Key_1].key)
    else if (event.key === Qt.Key_Down) moveSelection(1)
    else if (event.key === Qt.Key_Up) moveSelection(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (selectedRow()) activate(selectedRow()); else { moveSelection(1); activate(selectedRow()) } }
    else if (event.key === Qt.Key_Right && (!search.activeFocus || !query)) browse(selectedRow())
    else if (event.key === Qt.Key_Left && !search.activeFocus) back()
    else return
    event.accepted = true
  }
  onRowsChanged: {
    if (!rows.some(function(r) { return r.key === selectedKey })) selectedKey = ""
    if (displayRows) Model.syncList(displayRows, rows)
  }
  onMotionEnabledChanged: {
    if (!motionEnabled && list && refreshAction) {
      navigationMotion.stop()
      refreshSpin.stop()
      list.opacity = 1
      listShift.x = 0
      refreshAction.iconRotation = 0
    }
  }
  onOpenedChanged: {
    if (opened) {
      actionError = ""
      fetch()
      Qt.callLater(function() { search.forceActiveFocus() })
    } else {
      itemMenu.close()
      sessionMenu.close()
      navigationMotion.stop()
      refreshSpin.stop()
      list.opacity = 1
      listShift.x = 0
      refreshAction.iconRotation = 0
    }
  }
  Component.onCompleted: { Model.syncList(displayRows, rows); fetch() }

  ListModel { id: displayRows }
  ParallelAnimation {
    id: navigationMotion
    NumberAnimation { target: list; property: "opacity"; to: 1; duration: root.gentleMotion; easing.type: Easing.OutCubic }
    NumberAnimation { target: listShift; property: "x"; to: 0; duration: root.gentleMotion; easing.type: Easing.OutCubic }
  }
  NumberAnimation { id: refreshSpin; target: refreshAction; property: "iconRotation"; from: 0; to: 360; duration: 400; easing.type: Easing.OutCubic }

  Timer { interval: root.opened ? root.openRefreshMs : root.closedRefreshMs; running: true; repeat: true; onTriggered: { root.now = Date.now(); root.fetch() } }
  Timer { id: feedbackTimer; interval: 1800; onTriggered: root.feedbackText = "" }
  Process {
    id: fetchProc
    property string session: ""
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      // Ignore old scope responses, then immediately request the new session.
      if (session !== root.selectedSession) { root.fetch(); return }
      // Keep a context menu attached to the item the user actually clicked.
      if (itemMenu.visible || sessionMenu.visible) return
      try {
        var data = JSON.parse(fetchOut.text)
        if (exitCode !== 0 || !data.ok) throw new Error(data.error || "Could not read session data.")
        var scrollPosition = list.contentY
        root.snapshot = data
        root.hasSnapshot = true
        root.errorText = data.bridge === "connected" ? "" : "Herdr bridge disconnected."
        Qt.callLater(function() { list.contentY = Math.max(0, Math.min(scrollPosition, list.contentHeight - list.height)) })
      } catch (error) { root.errorText = String(error.message || "Could not read session data.") }
    }
  }
  Process {
    id: focusProc
    stdout: StdioCollector { id: focusOut; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var result = JSON.parse(focusOut.text)
        if (exitCode !== 0 || !result.ok) throw new Error(result.error || "Could not focus this item in Herdr.")
        root.close()
      } catch (error) { root.actionError = String(error.message || "Herdr did not respond. Try again.") }
    }
  }
  Process {
    id: launchProc
    onExited: function(exitCode) {
      if (exitCode === 0) root.close()
      else root.actionError = "Could not open Collie in your browser."
    }
  }

  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Den · " + (!root.connected ? "unavailable" : root.blockedCount + " needs you · " + root.readyCount + " ready · " + root.workingCount + " working")
    iconComponent: Component {
      Item {
        implicitWidth: Style.space(16); implicitHeight: Style.space(16)
        DenIcon { anchors.fill: parent; color: root.bar ? root.bar.foreground : root.foreground; opacity: root.connected ? 1 : 0.5 }
        Rectangle {
          opacity: Boolean(root.setting("showAttentionCount", true)) && root.connected && root.blockedCount + root.readyCount > 0 ? 1 : 0
          visible: opacity > 0
          anchors.right: parent.right; anchors.top: parent.top
          width: Style.space(6); height: width; radius: width / 2
          color: root.blockedCount ? root.urgent : root.ready
          Behavior on opacity { NumberAnimation { duration: root.gentleMotion } }
          Behavior on color { ColorAnimation { duration: root.gentleMotion } }
        }
      }
    }
    onPressed: function(button) {
      if (button === Qt.MiddleButton) root.openWeb(null)
      else if (button === Qt.RightButton) root.nextSession()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: search
    padding: Style.space(10)
    borderSpec: Border.flat(root.alpha(root.foreground, 0.22), 1)
    contentWidth: panel.fittedContentWidth(Math.max(320, Number(root.setting("panelWidth", 400))), Style.space(560))
    contentHeight: panel.fittedContentHeight(chrome.implicitHeight + Math.min(Style.space(285), Math.max(root.rows.length ? root.rowsHeight : Style.space(70), root.query ? root.unfilteredRowsHeight : 0)) + footer.height + Style.space(12), Style.space(430))
    Behavior on contentHeight {
      enabled: root.opened && root.motionEnabled && navigationMotion.running
      NumberAnimation { duration: root.gentleMotion; easing.type: Easing.OutCubic }
    }

    FocusScope {
      id: content
      anchors.fill: parent
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      Column {
        id: chrome
        width: parent.width
        spacing: Style.space(5)

        RowLayout {
          width: parent.width
          height: Style.space(28)
          spacing: Style.space(6)
          DenIcon { color: root.foreground; Layout.preferredWidth: Style.space(21); Layout.preferredHeight: Style.space(21) }
          Label { text: "Den"; font.pixelSize: Style.font.title; font.bold: true; Layout.fillWidth: true }
          Rectangle {
            id: destinationSwitch
            implicitWidth: Style.space(121); implicitHeight: Style.space(26)
            radius: Style.space(5); color: root.alpha(root.foreground, 0.05)
            Rectangle {
              x: Style.space(2) + (root.opensHerdr ? width + Style.space(2) : 0)
              y: Style.space(2)
              width: (parent.width - Style.space(6)) / 2; height: parent.height - Style.space(4)
              radius: Style.space(3); color: root.alpha(root.foreground, 0.12)
              Behavior on x { enabled: root.opened; NumberAnimation { duration: root.gentleMotion; easing.type: Easing.OutCubic } }
            }
            Row {
              anchors.fill: parent; anchors.margins: Style.space(2); spacing: Style.space(2)
              Action {
                width: (parent.width - parent.spacing) / 2; height: parent.height
                text: "Collie"; chosen: !root.opensHerdr; selectionFill: false
                Accessible.role: Accessible.RadioButton
                Accessible.checked: chosen
                hint: "Open selected rows in Collie's web dashboard"
                onClicked: root.saveSetting("navigationTarget", "Collie dashboard")
              }
              Action {
                width: (parent.width - parent.spacing) / 2; height: parent.height
                text: "Herdr"; chosen: root.opensHerdr; selectionFill: false
                Accessible.role: Accessible.RadioButton
                Accessible.checked: chosen
                hint: "Focus selected rows in Herdr terminal"
                onClicked: root.saveSetting("navigationTarget", "Herdr terminal")
              }
            }
          }
          Action { id: refreshAction; text: "↻"; hint: "Refresh · Ctrl+R"; enabled: !root.refreshing; onClicked: root.refreshNow() }
          Action { text: "↗"; hint: "Open Collie dashboard · Ctrl+O"; onClicked: root.openWeb(null) }
        }

        Item {
          id: categoryBar
          width: parent.width
          height: Style.space(27)
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.line }
          Rectangle {
            anchors.bottom: parent.bottom
            x: Math.max(0, root.categories.findIndex(function(c) { return c.key === root.category })) * (parent.width / 4) + Style.space(12)
            width: parent.width / 4 - Style.space(24); height: Style.space(2); radius: height / 2
            color: root.alpha(root.foreground, 0.8)
            Behavior on x { enabled: root.opened; NumberAnimation { duration: root.gentleMotion; easing.type: Easing.OutCubic } }
          }
          Row {
            anchors.fill: parent
            Repeater {
              model: root.categories
              delegate: Action {
                id: categoryAction
                required property var modelData
                required property int index
                readonly property int itemCount: root[modelData.key].length
                width: parent.width / 4; height: parent.height - Style.space(3)
                chosen: root.category === modelData.key
                selectionFill: false
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.title + ", " + itemCount
                Accessible.selected: chosen
                hint: modelData.title + " · Ctrl+" + (index + 1)
                contentItem: Item {
                  Row {
                    anchors.centerIn: parent; spacing: Style.space(5)
                    Label { text: categoryAction.modelData.title; font.pixelSize: Style.font.caption; font.bold: categoryAction.chosen; color: categoryAction.chosen ? root.foreground : root.muted; Behavior on color { ColorAnimation { duration: root.quickMotion } } }
                    Label { text: categoryAction.itemCount; font.pixelSize: Style.font.caption; color: root.muted; opacity: 0.75 }
                  }
                }
                onClicked: root.setView(modelData.key)
              }
            }
          }
        }

        RowLayout {
          visible: root.breadcrumbs.length > 0
          width: parent.width; height: Style.space(25); spacing: Style.space(4)
          Action { text: "‹"; hint: "Back"; onClicked: root.back() }
          Label { text: root.scope ? root.scope.title : ""; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
          Action { text: "Open ↗"; hint: "Open in " + root.destination(root.scope); onClicked: root.activate(root.scope) }
        }

        Rectangle {
          width: parent.width; height: Style.space(26); radius: Style.space(4)
          color: root.alpha(root.foreground, search.activeFocus && !root.selectedKey ? 0.035 : 0.02)
          border.width: 1; border.color: root.alpha(root.foreground, search.activeFocus && !root.selectedKey ? 0.20 : 0.08)
          Behavior on color { ColorAnimation { duration: root.quickMotion } }
          Behavior on border.color { ColorAnimation { duration: root.quickMotion } }
          Label { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: root.muted; font.pixelSize: Style.font.title }
          Controls.TextField {
            id: search
            anchors.fill: parent; anchors.leftMargin: Style.space(25); anchors.rightMargin: Style.space(28)
            text: root.query
            placeholderText: root.view === "detail" ? "Search " + (root.scope && root.scope.kind === "tab" ? "this tab…" : "this space…") : "Search " + root.view + "…"
            Accessible.name: placeholderText.replace("…", "")
            font.family: root.fontFamily; font.pixelSize: Style.font.caption
            color: root.foreground; placeholderTextColor: root.muted
            selectionColor: root.alpha(root.foreground, 0.25); selectedTextColor: root.foreground
            padding: 0; background: Item {}
            onTextEdited: { root.query = text; root.selectedKey = ""; list.positionViewAtBeginning() }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape || event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) || (event.key === Qt.Key_Right && !root.query && root.selectedKey) || (event.modifiers & Qt.ControlModifier)) root.handleKey(event)
            }
          }
          Action {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            opacity: root.query !== "" ? 1 : 0; visible: opacity > 0; enabled: root.query !== ""
            text: "×"; hint: "Clear search"
            Behavior on opacity { NumberAnimation { duration: root.quickMotion } }
            onClicked: { root.query = ""; search.forceActiveFocus() }
          }
        }

        Rectangle {
          visible: root.errorText !== "" || root.actionError !== ""
          width: parent.width; height: warning.implicitHeight + Style.space(12)
          radius: Style.space(4); color: root.alpha(root.urgent, 0.08)
          Label {
            id: warning
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(6)
            text: root.actionError || (root.errorText + (root.hasSnapshot ? " Showing cached data." : ""))
            font.pixelSize: Style.font.caption; color: root.urgent; wrapMode: Text.Wrap
          }
        }
      }

      ListView {
        id: list
        anchors.top: chrome.bottom; anchors.topMargin: Style.space(5)
        anchors.bottom: footer.top; anchors.bottomMargin: Style.space(6)
        width: parent.width
        model: displayRows
        clip: true
        transform: Translate { id: listShift }
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded; width: Style.space(4) }
        delegate: Item {
          id: listRow
          required property string payload
          readonly property var modelData: JSON.parse(payload)
          required property int index
          width: list.width; height: modelData.kind === "heading" ? root.headingHeight : root.rowHeight

          RowLayout {
            visible: listRow.modelData.kind === "heading"
            anchors.fill: parent; spacing: Style.space(5)
            Action {
              Layout.fillWidth: true; height: parent.height
              text: (listRow.modelData.collapsible ? (root.recentOpen || root.query ? "⌄ " : "› ") : "") + listRow.modelData.title + "  " + listRow.modelData.count
              textColor: root.tone(listRow.modelData.score)
              leftAligned: true; enabled: !!listRow.modelData.collapsible
              hint: listRow.modelData.collapsible ? "Expand or collapse recent agents" : ""
              onClicked: root.saveSetting("recentOpen", !root.recentOpen)
            }
            Action {
              visible: !!listRow.modelData.collapsible
              text: root.recentNewest ? "↓ Newest" : "↑ Oldest"
              height: parent.height; implicitWidth: Style.space(66)
              hint: "Sort by last seen time"
              onClicked: root.saveSetting("recentNewest", !root.recentNewest)
            }
          }

          Controls.AbstractButton {
            id: rowButton
            visible: listRow.modelData.kind !== "heading"
            anchors.fill: parent
            enabled: !focusProc.running && !launchProc.running
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            Accessible.name: listRow.modelData.title + ". " + listRow.modelData.detail
            Accessible.description: "Open in " + root.destination(listRow.modelData)
            onClicked: { root.selectedKey = listRow.modelData.key; root.activate(listRow.modelData) }
            Keys.onRightPressed: root.browse(listRow.modelData)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                root.showItemMenu(listRow.modelData, rowButton, Style.space(24), rowButton.height)
                event.accepted = true
              }
            }
            onActiveFocusChanged: if (activeFocus) root.selectedKey = listRow.modelData.key
            background: Rectangle {
              radius: Style.space(4)
              color: rowButton.down ? root.alpha(root.foreground, 0.14)
                : rowButton.activeFocus || root.selectedKey === listRow.modelData.key ? root.alpha(root.foreground, 0.08)
                : rowButton.hovered ? root.alpha(root.foreground, 0.045)
                : listRow.modelData.score >= 3 ? root.alpha(root.tone(listRow.modelData.score), 0.045) : "transparent"
              border.width: 1
              border.color: root.alpha(root.foreground, rowButton.activeFocus || root.selectedKey === listRow.modelData.key ? 0.22 : 0)
              Behavior on color { ColorAnimation { duration: root.quickMotion } }
              Behavior on border.color { ColorAnimation { duration: root.quickMotion } }
              Rectangle {
                opacity: listRow.modelData.score >= 3 || root.selectedKey === listRow.modelData.key ? 1 : 0
                x: 0; y: Style.space(8); width: Style.space(2); height: parent.height - Style.space(16); radius: 1
                color: listRow.modelData.score >= 3 ? root.tone(listRow.modelData.score) : root.alpha(root.foreground, 0.65)
                Behavior on opacity { NumberAnimation { duration: root.quickMotion } }
                Behavior on color { ColorAnimation { duration: root.gentleMotion } }
              }
            }
            contentItem: Item {
              Rectangle {
                x: Style.space(9); anchors.verticalCenter: parent.verticalCenter
                width: Style.space(6); height: width; radius: width / 2
                color: listRow.modelData.score >= 2 ? root.tone(listRow.modelData.score) : "transparent"
                border.width: listRow.modelData.score >= 2 ? 0 : 1; border.color: root.muted
                Behavior on color { ColorAnimation { duration: root.gentleMotion } }
              }
              Column {
                anchors.left: parent.left; anchors.leftMargin: Style.space(24)
                anchors.right: rowMeta.left; anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                Label { width: parent.width; text: listRow.modelData.title || ""; elide: Text.ElideRight; font.bold: listRow.modelData.score >= 3 }
                Label { width: parent.width; text: listRow.modelData.detail || ""; color: root.muted; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              }
              Row {
                id: rowMeta
                anchors.right: parent.right; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                Label {
                  anchors.verticalCenter: parent.verticalCenter
                  text: listRow.modelData.focused ? "active" : root.elapsed(listRow.modelData.stamp)
                  color: root.muted; font.pixelSize: Style.font.caption
                }
                Action {
                  visible: !!listRow.modelData.canBrowse
                  text: "›"; hint: listRow.modelData.kind === "space" ? "Browse tabs and panes" : "Browse panes"
                  onClicked: root.browse(listRow.modelData)
                }
              }
            }
            HoverTip {
              visible: rowButton.hovered && !rowButton.down && !itemMenu.visible
              delay: 650
              text: listRow.modelData.title + "\n" + listRow.modelData.detail + "\nOpen in " + root.destination(listRow.modelData) + " · Right-click for actions"
            }
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.RightButton
              onClicked: function(mouse) { root.showItemMenu(listRow.modelData, rowButton, mouse.x, mouse.y) }
            }
          }
        }
        Column {
          visible: root.rows.length === 0
          anchors.centerIn: parent; width: parent.width - Style.space(20); spacing: Style.space(5)
          Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.refreshing && !root.hasSnapshot ? "Loading sessions…" : root.query ? "No matches" : root.errorText ? "Sessions unavailable" : "No " + (root.view === "detail" ? "panes" : root.view); font.bold: true }
          Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.query ? "Try a title, workspace, agent, or path." : root.errorText ? "Use ↻ to retry or ↗ to open the dashboard." : "New sessions appear automatically."; color: root.muted; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
        }
      }

      Item {
        id: footer
        anchors.bottom: parent.bottom; width: parent.width; height: Style.space(24)
        Rectangle { width: parent.width; height: 1; color: root.line }
        RowLayout {
          anchors.fill: parent; anchors.topMargin: Style.space(4); spacing: Style.space(5)
          Rectangle { Layout.preferredWidth: Style.space(5); Layout.preferredHeight: Style.space(5); radius: width / 2; color: root.connected ? root.ready : root.urgent }
          Action {
            id: sessionButton
            implicitWidth: Math.min(Style.space(130), sessionLabel.implicitWidth + Style.space(12))
            height: Style.space(20)
            text: root.activeSession + (root.sessions.length > 1 ? " ⌄" : "")
            hint: root.connected ? "Connected to Herdr · " + root.activeSession : "Session bridge unavailable"
            onClicked: if (root.sessions.length > 1) sessionMenu.open()
            Label { id: sessionLabel; visible: false; text: sessionButton.text; font.pixelSize: Style.font.caption }
            FadeMenu {
              id: sessionMenu
              y: -height
              onClosed: root.fetch()
              padding: Style.space(4)
              background: Rectangle { color: Color.popups.background; border.width: 1; border.color: root.line; radius: Style.space(4) }
              Instantiator {
                model: root.sessions
                delegate: Controls.MenuItem {
                  id: sessionOption
                  required property var modelData
                  text: modelData.name
                  checkable: true; checked: modelData.name === root.activeSession
                  contentItem: Label { text: (sessionOption.checked ? "✓ " : "  ") + sessionOption.text }
                  background: Rectangle { color: sessionOption.highlighted ? root.alpha(root.foreground, 0.1) : "transparent"; radius: Style.space(3); Behavior on color { ColorAnimation { duration: root.quickMotion } } }
                  onTriggered: root.selectSession(modelData.name)
                }
                onObjectAdded: function(index, object) { sessionMenu.insertItem(index, object) }
                onObjectRemoved: function(index, object) { sessionMenu.removeItem(object) }
              }
            }
          }
          Item { Layout.fillWidth: true }
          Label {
            text: focusProc.running || launchProc.running ? "Opening…" : root.feedbackText || (root.selectedRow() && root.selectedRow().canBrowse ? "→ browse  ↵ open" : "↑↓ select  ↵ open")
            color: root.feedbackText ? root.ready : root.muted; font.pixelSize: Style.font.caption
            Behavior on color { ColorAnimation { duration: root.quickMotion } }
          }
        }
      }

      FadeMenu {
        id: itemMenu
        property var row: null
        property string link: ""
        readonly property var workspace: row ? Model.workspace(root.snapshot, row.item) : null
        parent: content
        width: Style.space(232)
        padding: Style.space(4)
        margins: Style.space(8)
        onClosed: root.fetch()
        background: Rectangle { color: Color.popups.background; border.width: 1; border.color: root.alpha(root.foreground, 0.24); radius: Style.space(6) }

        ContextAction { text: itemMenu.row ? itemMenu.row.title : ""; enabled: false; heading: true }
        ContextAction {
          text: itemMenu.row && itemMenu.row.item.host ? "Herdr · local items only" : "Open in Herdr terminal"
          enabled: itemMenu.row !== null && !itemMenu.row.item.host
          onTriggered: root.activate(itemMenu.row, "Herdr terminal")
        }
        ContextAction { text: "Open in Collie dashboard"; onTriggered: root.openWeb(itemMenu.row) }
        ContextAction {
          visible: itemMenu.row !== null && itemMenu.row.canBrowse
          text: itemMenu.row && itemMenu.row.kind === "space" ? "Browse tabs and panes" : "Browse panes"
          onTriggered: root.browse(itemMenu.row)
        }
        ContextAction {
          visible: itemMenu.row !== null && itemMenu.row.kind !== "space" && itemMenu.workspace !== undefined && itemMenu.workspace !== null
          text: "Show workspace"
          onTriggered: root.browseWorkspace(itemMenu.row)
        }
        Controls.MenuSeparator {
          padding: Style.space(4)
          contentItem: Rectangle { implicitHeight: 1; color: root.line }
        }
        ContextAction { text: "Copy Collie dashboard link"; onTriggered: root.copyDetail(itemMenu.link, "link") }
        ContextAction {
          visible: itemMenu.row !== null && !!itemMenu.row.item.cwd
          text: "Copy working directory"
          onTriggered: root.copyDetail(itemMenu.row.item.cwd, "path")
        }
        ContextAction {
          text: "Copy item ID"
          onTriggered: root.copyDetail(itemMenu.row.item.paneId || itemMenu.row.item.tabId || itemMenu.row.item.workspaceId, "ID")
        }
      }
    }
  }

  component FadeMenu: Controls.Menu {
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.quickMotion; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.motionEnabled ? 80 : 0; easing.type: Easing.OutCubic } }
  }

  component ContextAction: Controls.MenuItem {
    id: option
    property bool heading: false
    implicitHeight: Style.space(28)
    height: visible ? implicitHeight : 0
    leftPadding: Style.space(8)
    rightPadding: Style.space(8)
    hoverEnabled: true
    indicator: Item {}
    contentItem: Label {
      text: option.text
      color: option.enabled ? root.foreground : root.muted
      font.bold: option.heading
      font.pixelSize: option.heading ? Style.font.caption : Style.font.bodySmall
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    background: Rectangle { color: option.enabled && (option.highlighted || option.hovered) ? root.alpha(root.foreground, 0.1) : "transparent"; radius: Style.space(3); Behavior on color { ColorAnimation { duration: root.quickMotion } } }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  component HoverTip: Controls.ToolTip {
    id: tip
    padding: Style.space(7)
    delay: 600
    background: Rectangle { color: Color.popups.background; border.width: 1; border.color: root.alpha(root.foreground, 0.2); radius: Style.space(4) }
    contentItem: Label { text: tip.text; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap; width: Math.min(implicitWidth, Style.space(320)) }
  }
  component Action: Controls.AbstractButton {
    id: action
    property string hint: ""
    property bool chosen: false
    property bool selectionFill: true
    property real iconRotation: 0
    property bool leftAligned: false
    property color textColor: chosen ? root.foreground : root.muted
    implicitWidth: Math.max(Style.space(24), actionText.implicitWidth + Style.space(12))
    implicitHeight: Style.space(24)
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    Accessible.name: hint || text
    Keys.onReturnPressed: if (enabled) clicked()
    Keys.onEnterPressed: if (enabled) clicked()
    background: Rectangle {
      radius: Style.space(4)
      color: !action.enabled ? "transparent" : action.down ? root.alpha(root.foreground, 0.14) : action.hovered || action.activeFocus ? root.alpha(root.foreground, 0.07) : action.chosen && action.selectionFill ? root.alpha(root.foreground, 0.12) : "transparent"
      border.width: 1; border.color: root.alpha(root.foreground, action.activeFocus ? 0.35 : 0)
      Behavior on color { ColorAnimation { duration: root.quickMotion } }
      Behavior on border.color { ColorAnimation { duration: root.quickMotion } }
    }
    contentItem: Label {
      id: actionText
      text: action.text; color: action.textColor
      rotation: action.iconRotation
      Behavior on color { ColorAnimation { duration: root.quickMotion } }
      font.pixelSize: Style.font.caption; font.bold: action.chosen
      horizontalAlignment: action.leftAligned ? Text.AlignLeft : Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    HoverHandler { cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    HoverTip { visible: action.hovered && action.hint !== ""; text: action.hint }
  }
}
