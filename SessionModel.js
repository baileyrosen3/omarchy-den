// Pure snapshot/view logic, shared by the QML popup and regression checks.
function items(snapshot, name) { return Array.isArray(snapshot[name]) ? snapshot[name] : [] }
function host(item) { return String(item.host || "") }
function sameScope(a, b) { return host(a) === host(b) }
function key(kind, item) { return kind + ":" + host(item) + ":" + String(item.paneId || item.tabId || item.workspaceId) }
function bucket(item) {
  if (item.status === "blocked") return "needs"
  if (item.status === "done" && Number(item.lastActiveAt || 0) > Number(item.lastSeenAt || 0)) return "ready"
  return item.status === "working" ? "working" : "recent"
}
function rank(item) { return {needs: 4, ready: 3, working: 2, recent: 1}[bucket(item)] }
function countLabel(count, name) { return Number(count || 0) + " " + name + (Number(count || 0) === 1 ? "" : "s") }
function workspace(snapshot, item) {
  return items(snapshot, "workspaces").find(function(s) { return s.workspaceId === item.workspaceId && sameScope(s, item) })
}
function paneForTab(snapshot, tab) {
  var panes = items(snapshot, "agents").concat(items(snapshot, "shellPanes")).filter(function(p) {
    return p.tabId === tab.tabId && sameScope(p, tab)
  })
  return panes.find(function(p) { return p.focused }) || panes[0]
}
function title(item, kind) {
  if (kind === "space") return String(item.label || "Workspace " + (item.number || ""))
  if (kind === "tab") {
    var label = String(item.label || item.number || "")
    return /^\d+$/.test(label) ? "Tab " + label : label || "Tab"
  }
  return String(item.paneLabel || item.sessionName || item.terminalTitle || item.cwd && item.cwd.split("/").filter(Boolean).pop() || item.agent || "Shell")
}
function row(snapshot, item, kind) {
  var space = workspace(snapshot, item)
  var place = String(item.workspaceLabel || (space && space.label) || item.workspaceId || "")
  var tab = item.tabLabel || (item.tabId ? item.tabId.split(":t").pop() : "")
  var agent = String(item.agent || "shell")
  var agentName = {codex: "Codex", claude: "Claude", omp: "Pi", shell: "Shell"}[agent] || agent
  var detail = kind === "space" ? countLabel(item.tabCount, "tab") + " · " + countLabel(item.paneCount, "pane")
    : kind === "tab" ? place + " · " + countLabel(item.paneCount, "pane")
    : place + (tab ? " / " + tab : "") + " · " + agentName
  if (item.host) detail += " · " + item.host
  var score = kind === "pane" ? rank(item) : 0
  if (kind !== "pane") items(snapshot, "agents").forEach(function(a) {
    if (sameScope(a, item) && a.workspaceId === item.workspaceId && (kind !== "tab" || a.tabId === item.tabId)) score = Math.max(score, rank(a))
  })
  var stamp = Number(item.lastSeenAt || item.lastActiveAt || 0)
  return {key: key(kind, item), kind: kind, item: item, title: title(item, kind), detail: detail,
    score: score, stamp: stamp, focused: !!item.focused, canBrowse: kind === "space" || kind === "tab"}
}
function matches(row, query) {
  var text = [row.title, row.detail, row.item.cwd || "", row.item.paneId || "", row.item.tabId || ""].join(" ").toLowerCase()
  return query.toLowerCase().trim().split(/\s+/).every(function(term) { return text.indexOf(term) >= 0 })
}
function build(snapshot, view, query, scope, recentOpen, newest) {
  var result = []
  function addRows(collection, kind, heading, tone, collapsible) {
    var rows = collection.map(function(item) { return row(snapshot, item, kind) }).filter(function(r) { return matches(r, query) })
    if (!rows.length) return
    if (heading) result.push({key: "heading:" + heading, kind: "heading", title: heading, count: rows.length, score: tone || 0, collapsible: !!collapsible})
    if (!collapsible || recentOpen || query.trim()) result = result.concat(rows)
  }
  function inScope(item) {
    return !scope || (sameScope(item, scope.item) && item.workspaceId === scope.item.workspaceId && (scope.kind !== "tab" || item.tabId === scope.item.tabId))
  }
  var agents = items(snapshot, "agents").filter(inScope)
  var shells = items(snapshot, "shellPanes").filter(inScope)
  var tabs = items(snapshot, "tabs").filter(inScope)
  function byNumber(a, b) { return Number(a.number || 0) - Number(b.number || 0) }
  function latest(a, b) { return Number(b.lastSeenAt || b.lastActiveAt || 0) - Number(a.lastSeenAt || a.lastActiveAt || 0) }
  if (view === "agents") {
    ["needs", "ready", "working", "recent"].forEach(function(b) {
      var group = agents.filter(function(a) { return bucket(a) === b }).sort(function(a, c) {
        if (b === "recent") return (newest ? 1 : -1) * latest(a, c)
        return Number(c.lastActiveAt || 0) - Number(a.lastActiveAt || 0)
      })
      addRows(group, "pane", {needs: "Needs you", ready: "Ready · unseen", working: "Working", recent: "Recent"}[b], {needs: 4, ready: 3, working: 2, recent: 0}[b], b === "recent")
    })
  } else if (view === "spaces") {
    var spaces = items(snapshot, "workspaces").slice().sort(function(a, b) {
      return row(snapshot, b, "space").score - row(snapshot, a, "space").score || byNumber(a, b)
    })
    addRows(spaces, "space")
  } else if (view === "tabs") addRows(tabs, "tab")
  else if (view === "shells") addRows(shells.sort(latest), "pane")
  else if (view === "detail") {
    if (scope && scope.kind === "space") addRows(tabs.sort(byNumber), "tab", "Tabs")
    addRows(agents.sort(function(a, b) { return rank(b) - rank(a) || latest(a, b) }), "pane", "Agents")
    addRows(shells.sort(latest), "pane", "Shells")
  }
  return result
}
function route(base, path, session, item) {
  // Preserve a configured base path/query and replace scope keys deliberately.
  var pieces = String(base).split("#")[0].split("?")
  var args = (pieces[1] || "").split("&").filter(function(p) { return p && !/^(s|h)=/.test(p) })
  if (session) args.push("s=" + encodeURIComponent(session))
  if (item && item.host) args.push("h=" + encodeURIComponent(item.host))
  return pieces[0].replace(/\/$/, "") + path + (args.length ? "?" + args.join("&") : "")
}
function webUrl(snapshot, base, session, selection) {
  var item = selection ? selection.item : null
  var kind = selection ? selection.kind : "dashboard"
  if (kind === "tab") {
    var pane = paneForTab(snapshot, item)
    if (pane) { item = pane; kind = "pane" }
    else kind = "space"
  }
  var path = kind === "pane" ? "/pane/" + encodeURIComponent(item.paneId)
    : kind === "space" ? "/space/" + encodeURIComponent(item.workspaceId) : ""
  return route(base, path, session, item)
}
