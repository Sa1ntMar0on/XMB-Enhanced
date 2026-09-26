pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "XmbModel.js" as XmbModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property string pendingInitialMenu: "root"
  property bool opened: false

  // SUPER+SPACE takeover: bound while the plugin is loaded, restored to the
  // Omarchy menu when it is disabled or its directory is removed. Detached so
  // the write survives the destroy that triggers it.
  Component.onCompleted: Util.execDetached("bash " + Util.shellQuote(root.pluginDir + "keybinding.sh") + " take")
  Component.onDestroyed: Util.execDetached("bash " + Util.shellQuote(root.pluginDir + "keybinding.sh") + " release")

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily
    root.openRoute(payload.initialMenu || payload.menu || "root")
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  function debugState() {
    return JSON.stringify({
      opened: root.opened,
      rowsLoaded: root.rowsLoaded,
      itemCount: Object.keys(root.items).length,
      categoryIds: root.categoryIds,
      categoryIndex: root.categoryIndex,
      nodeId: root.nodeId,
      depth: root.depth,
      selectedIndex: root.selectedIndex,
      displayCount: displayModel.count,
      iconCount: iconModel.count,
      scrim: root.scrim.toString(),
      foreground: root.foreground.toString(),
      selectedText: root.selectedText.toString(),
      panelWidth: content.width,
      panelHeight: content.height,
      contentW: content.width,
      contentH: content.height,
      itemListW: itemList.width,
      itemListH: itemList.height,
      iconRowW: iconRow.width,
      screen: panel.screen ? panel.screen.name : "none",
      shellInjected: !!root.shell,
      shellType: typeof root.shell,
      shellKeys: root.shell ? Object.keys(root.shell).join("|") : "",
      appLibValue: root.shell ? String(root.shell.appLibrary) : "no-shell",
      manifestKinds: root.manifest && root.manifest.kinds ? root.manifest.kinds.join(",") : "none",
      manifestId: root.manifest ? String(root.manifest.id || "") : "none",
      sourceDir: root.manifest && root.manifest.__sourceDir ? root.manifest.__sourceDir : "hidden",
      appLibrary: !!root.appLibrary,
      appEntries: root.appLibrary ? root.appLibrary.sortedEntries("").length : -1
    })
  }

  property string fontFamily: Style.font.menuFamily

  // Same JSONC sources the omarchy menu reads: defaults merged with the user
  // extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool rowsLoaded: false
  property var items: ({})
  property var itemOrder: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  property string filterText: ""
  property int selectedIndex: 0
  property int layoutSerial: 0

  // XMB navigation state.
  property string nodeId: "root"
  property var categoryIds: []
  property int categoryIndex: 0
  property int depth: 0

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  // Directory of this plugin (resolved from the QML URL), used to locate the
  // bundled apps-list.sh fallback enumerator.
  readonly property string pluginDir: {
    var path = Qt.resolvedUrl(".").toString()
    if (path.indexOf("file://") === 0) path = path.slice(7)
    return decodeURIComponent(path)
  }

  function iconSourceFor(appIcon) {
    if (root.appLibrary) return root.appLibrary.iconSource(appIcon)
    var value = String(appIcon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedText: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property color scrim: Color.menu.scrim
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius

  // Layout, proportions taken from the reference XMB screenshot. Anchored to
  // the content Item that fills the PanelWindow — the plugin root Item itself
  // has no size of its own.
  readonly property real anchorX: content.width * 0.245
  readonly property real columnIconCenter: content.width * 0.235
  readonly property real rowCenterY: content.height * 0.25
  readonly property real colTop: content.height * 0.12
  readonly property real colBottom: content.height * 0.94
  readonly property real pinY: content.height * 0.40
  readonly property int rowItemHeight: Math.max(Style.space(50), Style.font.body + Style.space(38))
  readonly property int rowSpacing: Style.space(4)
  readonly property int iconSpacing: Style.space(150)
  readonly property int iconRowDelegateHeight: Style.space(130)
  readonly property int fadeBand: Style.space(56)
  readonly property int columnWidth: Math.min(Style.space(640), content.width * 0.55)

  readonly property string nodeLabel: {
    var entry = root.item(root.nodeId)
    return entry ? (entry.title || entry.label) : ""
  }

  readonly property string breadcrumbText: {
    if (root.depth <= 0) return "OMARCHY / XMB"
    var labels = []
    var id = root.nodeId
    while (id && id !== "root") {
      var entry = root.item(id)
      if (!entry) break
      labels.unshift(entry.title || entry.label)
      id = entry.parent
    }
    return ("OMARCHY / XMB / " + labels.join(" / ")).toUpperCase()
  }

  function item(id) {
    return root.items[id] || null
  }

  function stripJsonc(raw) { return XmbModel.stripJsonc(raw) }
  function normalizeItem(id, raw) { return XmbModel.normalizeItem(id, raw) }
  function parseMenuJsonc(raw) { return XmbModel.parseMenuJsonc(raw) }
  function slugify(value) { return XmbModel.slugify(value) }

  function rebuildItemsFromSources() {
    var mergedMenu = XmbModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.refreshCategories()
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.filterText.trim()) root.loadProviderForMenu(root.nodeId)
      else root.loadProvidersForSearch()
    }
  }

  function refreshCategories() {
    var ids = []
    for (var i = 0; i < root.itemOrder.length; i++) {
      var child = root.item(root.itemOrder[i])
      if (!child || child.parent !== "root") continue
      if (!root.isVisible(child)) continue
      ids.push(child.id)
    }
    root.categoryIds = ids
    if (root.categoryIndex >= ids.length || root.categoryIndex < 0) root.categoryIndex = 0
    iconModel.clear()
    for (var j = 0; j < ids.length; j++) {
      var entry = root.item(ids[j])
      iconModel.append({
        catId: ids[j],
        icon: entry.icon || "",
        iconFont: entry.iconFont || "",
        label: entry.title || entry.label || ids[j]
      })
    }
    iconRow.currentIndex = root.categoryIndex
  }

  function childEntries(id) {
    var entry = root.item(id)
    var out = []
    if (entry && entry.kind === "action") return [entry]
    for (var i = 0; i < root.itemOrder.length; i++) {
      var child = root.item(root.itemOrder[i])
      if (!child || child.parent !== id) continue
      if (!root.isVisible(child)) continue
      out.push(child)
    }
    return out
  }

  readonly property var providers: ({
    "apps-bash": {
      script: "bash " + Util.shellQuote(root.pluginDir + "apps-list.sh"),
      icon: "",
      volatile: true,
      actionFor: function(value) {
        return "uwsm-app -- gtk-launch " + Util.shellQuote(value + ".desktop")
      }
    },
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = XmbModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.refreshCategories()
    if (root.opened) root.rebuildDisplay()
  }

  // The host wires appLibrary only for menu-kind plugins; when it is missing
  // (scoped shell quirk), apps fall back to the bundled bash enumerator.
  function providerKeyFor(entry) {
    if (entry.provider === "apps" && !root.appLibrary) return "apps-bash"
    return entry.provider
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps" && root.appLibrary) {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var providerKey = root.providerKeyFor(entry)
    var spec = root.providers[providerKey]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = providerKey
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      var icon = parts[3] || ""
      if (!label) continue
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: providerKey === "apps-bash" ? "app" : "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        iconFont: "",
        appIcon: icon,
        appId: providerKey === "apps-bash" ? value : "",
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = XmbModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.refreshCategories()
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider) return
    var spec = root.providers[root.providerKeyFor(entry)]
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var scopeId = root.depth > 0 ? root.nodeId : "root"
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (entry.id !== scopeId && !root.isDescendantOf(entry.id, scopeId)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) { return XmbModel.depthFor(root.items, id) }
  function pathFor(id) { return XmbModel.pathFor(root.items, id) }
  function parentPathFor(id) { return XmbModel.parentPathFor(root.items, id) }
  function isDescendantOf(id, ancestorId) { return XmbModel.isDescendantOf(root.items, id, ancestorId) }
  function isVisible(entry) { return XmbModel.isVisible(root.items, root.itemOrder, root.whenResults, entry) }
  function labelFor(entry) { return XmbModel.labelFor(entry, root.checkedResults) }
  function matchesQuery(entry, query) { return XmbModel.matchesQuery(entry, query, root.isVisible(entry)) }
  function searchScore(entry, query) { return XmbModel.searchScore(root.items, entry, query) }
  function displayRow(entry, detail, score, section) {
    return XmbModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDisplay() {
    displayModel.clear()

    if (!root.rowsLoaded) return

    var rows = []
    var query = root.filterText.trim()

    if (query) {
      // Global search at the category level, scoped to the open subtree
      // once drilled in — matches the omarchy menu's behavior.
      var scopeId = root.depth > 0 ? root.nodeId : "root"
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, scopeId)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === scopeId) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      rows = currentRows.concat(drilldownRows)
    } else {
      var children = root.childEntries(root.nodeId)
      for (var j = 0; j < children.length; j++) {
        var child = children[j]
        rows.push(root.displayRow(child, child.description, child.order))
      }

      if (root.nodeId === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    itemList.currentIndex = root.selectedIndex
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    var next = (itemList.currentIndex + delta + displayModel.count) % displayModel.count
    itemList.currentIndex = next
    root.selectedIndex = next
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.disarmPointer()
    if (root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setCategory(index, fromPointer) {
    if (root.categoryIds.length === 0) return
    var count = root.categoryIds.length
    var next = ((index % count) + count) % count
    root.categoryIndex = next
    iconRow.currentIndex = next
    root.nodeId = root.categoryIds[next]
    root.depth = 0
    root.filterText = ""
    root.selectedIndex = 0
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(root.nodeId)
    root.loadProviderForMenu(root.nodeId)
  }

  function moveCategory(delta) {
    root.setCategory(root.categoryIndex + delta, false)
  }

  function drillInto(id, fromPointer) {
    if (!root.item(id)) return
    root.nodeId = id
    root.depth = Math.max(0, XmbModel.depthFor(root.items, id))
    root.filterText = ""
    root.selectedIndex = 0
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goUp() {
    if (root.depth <= 0) return false
    var entry = root.item(root.nodeId)
    var parent = entry && entry.parent ? entry.parent : "root"
    root.nodeId = parent
    root.depth -= 1
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
    root.invalidateVolatileProvider(root.nodeId)
    root.loadProviderForMenu(root.nodeId)
    return true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return
    Util.execDetached(command)
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.drillInto(row.target || row.itemId, fromPointer)
    } else if (row.kind === "app") {
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(row.appId, row.label)
      else root.runAction(row.action)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    opened = false
    filterText = ""
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    itemList.currentIndex = index
    root.selectedIndex = index
  }

  function openExistingMenu(initialMenu) {
    root.refreshCategories()
    var id = root.item(initialMenu) ? initialMenu : "root"

    if (id === "root" || !root.item(id)) {
      root.categoryIndex = 0
      root.nodeId = root.categoryIds.length > 0 ? root.categoryIds[0] : "root"
      root.depth = 0
    } else {
      var chain = []
      var cur = root.item(id)
      while (cur && cur.parent && cur.parent !== "root") {
        chain.unshift(cur.id)
        cur = root.item(cur.parent)
      }
      if (cur && cur.id !== "root" && cur.parent === "root") {
        var idx = root.categoryIds.indexOf(cur.id)
        if (idx >= 0) root.categoryIndex = idx
        root.nodeId = id
        root.depth = chain.length
      } else {
        root.categoryIndex = 0
        root.nodeId = root.categoryIds.length > 0 ? root.categoryIds[0] : "root"
        root.depth = 0
      }
    }

    filterText = ""
    selectedIndex = 0
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(root.nodeId)
    loadProviderForMenu(root.nodeId)
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function resolveRoute(input) {
    return XmbModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  ListModel { id: displayModel }
  ListModel { id: iconModel }

  property var whenResults: ({})
  property var checkedResults: ({})
  property bool guardsPending: false

  function evaluateGuards() {
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = XmbModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.refreshCategories()
      if (root.opened) root.rebuildDisplay()
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: itemList
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "picard-xmb"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrimRect
      anchors.fill: parent
      color: root.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Item {
      id: content
      anchors.fill: parent
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }

      Text {
        id: breadcrumb
        anchors.top: parent.top
        anchors.topMargin: content.height * 0.105
        anchors.right: parent.right
        anchors.rightMargin: content.width * 0.08
        textFormat: Text.PlainText
        text: root.breadcrumbText
        color: root.selectedText
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.letterSpacing: Style.space(2)
      }

      Text {
        id: categoryLabel
        anchors.top: parent.top
        anchors.topMargin: root.rowCenterY + root.iconRowDelegateHeight * 0.5
        x: root.columnIconCenter - root.columnWidth * 0.12
        textFormat: Text.PlainText
        text: root.filterText.trim() ? (root.nodeLabel + "  ▏ " + root.filterText) : root.nodeLabel
        color: root.selectedText
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.heading * 1.5)
        font.weight: Font.DemiBold
      }

      Item {
        id: columnClip
        anchors.top: parent.top
        anchors.topMargin: root.colTop
        anchors.bottom: parent.bottom
        anchors.bottomMargin: content.height - root.colBottom
        x: root.columnIconCenter - Style.space(24)
        width: root.columnWidth
        clip: true

        ListView {
          id: itemList
          anchors.fill: parent
          model: displayModel
          clip: false
          spacing: root.rowSpacing
          boundsBehavior: Flickable.StopAtBounds
          highlightRangeMode: ListView.StrictlyEnforceRange
          snapMode: ListView.SnapToItem
          highlightMoveDuration: 200
          highlightMoveVelocity: -1
          preferredHighlightBegin: root.pinY - root.colTop
          preferredHighlightEnd: root.pinY - root.colTop + root.rowItemHeight
          onCurrentIndexChanged: root.selectedIndex = itemList.currentIndex

          delegate: Item {
            id: rowDelegate
            required property int index
            required property string itemId
            required property string kind
            required property string icon
            required property string iconFont
            required property string appIcon
            required property string appId
            required property string label
            required property string target
            required property string detail
            required property string path
            required property string action

            readonly property bool isSelected: rowDelegate.index === root.selectedIndex && displayModel.count > 0
            readonly property bool isApp: rowDelegate.kind === "app"
            readonly property bool hasIcon: rowDelegate.icon.length > 0 || rowDelegate.isApp

            width: ListView.view.width
            height: root.rowItemHeight

            readonly property real vpY: rowDelegate.y - itemList.contentY
            readonly property real edgeFadeTop: Math.max(0, Math.min(1, (vpY + height) / root.fadeBand))
            readonly property real edgeFadeBottom: Math.max(0, Math.min(1, (itemList.height - vpY) / root.fadeBand))
            opacity: (isSelected ? 1 : 0.62) * edgeFadeTop * edgeFadeBottom

            BorderSurface {
              visible: rowDelegate.isSelected
              anchors.fill: parent
              radius: root.cornerRadius
              color: root.selectedBackground
              borderSpec: root.selectedBorderSpec
            }

            Image {
              id: appIconImage
              visible: rowDelegate.isApp
              width: rowDelegate.isSelected ? Style.font.iconLarge * 2 : Style.font.iconLarge
              height: width
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: rowDelegate.isApp ? root.iconSourceFor(rowDelegate.appIcon) : ""
              asynchronous: true
              anchors.left: parent.left
              anchors.leftMargin: (Style.space(48) - width) / 2
              anchors.verticalCenter: parent.verticalCenter
              Behavior on width { NumberAnimation { duration: 140 } }
            }

            Text {
              id: itemIcon
              visible: rowDelegate.hasIcon && !rowDelegate.isApp
              textFormat: Text.PlainText
              text: rowDelegate.icon
              color: rowDelegate.isSelected ? root.selectedText : root.foreground
              font.family: rowDelegate.iconFont.length > 0 ? rowDelegate.iconFont : root.fontFamily
              font.pixelSize: rowDelegate.isSelected ? Style.font.iconLarge * 2.2 : Style.font.iconLarge * 1.2
              width: Style.space(48)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              Behavior on font.pixelSize { NumberAnimation { duration: 140 } }
            }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(56)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: rowDelegate.label
                color: rowDelegate.isSelected ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: rowDelegate.isSelected ? Style.font.heading * 1.75 : Style.font.heading * 1.15
                elide: Text.ElideRight
                Behavior on font.pixelSize { NumberAnimation { duration: 140 } }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: rowDelegate.detail
                visible: root.filterText.trim() && rowDelegate.detail.length > 0
                color: root.foreground
                opacity: 0.52
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            MouseArea {
              id: mouseArea2
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectFromPointer(rowDelegate.index, rowDelegate, {
                x: mouseArea2.mouseX,
                y: mouseArea2.mouseY
              })
              onPositionChanged: function(mouse) {
                root.selectFromPointer(rowDelegate.index, rowDelegate, mouse)
              }
              onClicked: {
                itemList.currentIndex = rowDelegate.index
                root.selectedIndex = rowDelegate.index
                root.activateIndex(rowDelegate.index, true)
              }
            }

            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          visible: displayModel.count === 0

          Text {
            textFormat: Text.PlainText
            text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }
      }

      ListView {
        id: iconRow
        anchors.top: parent.top
        anchors.topMargin: root.rowCenterY - root.iconRowDelegateHeight / 2
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.iconRowDelegateHeight
        orientation: ListView.Horizontal
        model: iconModel
        interactive: false
        clip: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        snapMode: ListView.SnapToItem
        highlightMoveDuration: 220
        highlightMoveVelocity: -1
        preferredHighlightBegin: root.anchorX - root.iconSpacing / 2
        preferredHighlightEnd: root.anchorX + root.iconSpacing / 2

        delegate: Item {
          id: catDelegate
          required property int index
          required property string catId
          required property string icon
          required property string iconFont
          required property string label

          width: root.iconSpacing
          height: root.iconRowDelegateHeight

          readonly property bool isSelected: catDelegate.index === root.categoryIndex
          readonly property int distance: Math.abs(catDelegate.index - root.categoryIndex)
          opacity: isSelected ? 1 : Math.max(0.16, 0.4 - distance * 0.05)

          Text {
            id: catGlyph
            textFormat: Text.PlainText
            text: catDelegate.icon
            color: root.foreground
            font.family: catDelegate.iconFont.length > 0 ? catDelegate.iconFont : root.fontFamily
            font.pixelSize: Style.space(44)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            scale: catDelegate.isSelected ? 1.3 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
          }

          Text {
            visible: catDelegate.isSelected
            textFormat: Text.PlainText
            text: catDelegate.label
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: catGlyph.verticalCenter
            anchors.topMargin: Style.space(30)
            opacity: root.depth > 0 ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setCategory(catDelegate.index, true)
            onWheel: function(wheel) {
              root.moveCategory(wheel.angleDelta.y < 0 ? 1 : -1)
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.NoButton
          onWheel: function(wheel) {
            root.moveCategory(wheel.angleDelta.y < 0 ? 1 : -1)
          }
        }
      }

      Text {
        id: hintBar
        anchors.right: parent.right
        anchors.rightMargin: Style.space(60)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(26)
        textFormat: Text.PlainText
        text: "←→ category   ↑↓ item   enter select   backspace back   esc close"
        color: root.foreground
        opacity: 0.3
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 5
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (!root.goUp()) root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText) root.setFilter("")
            else if (!root.goUp()) root.cancel()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.disarmPointer()
            if (root.filterText) root.setFilter("")
            else root.moveCategory(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.disarmPointer()
            if (root.filterText) root.setFilter("")
            else root.moveCategory(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex, false)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }
    }
  }

  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }

  function requestDeleteSelected() {
    if (selectedIndex < 0 || selectedIndex >= displayModel.count) return
    var row = displayModel.get(selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
    else Util.execDetached("omarchy-remove-launcher-entry " + Util.shellQuote(target.appId) + " " + Util.shellQuote(target.label))
  }
}