<img src="docs/swarm.svg" width="64" alt="Swarm honeycomb mark">

# Swarm

**Your agents, workspaces, tabs, and shells—one compact Omarchy popup.**

Swarm brings session triage to the navbar. See which agents need you, find the
right workspace, and jump directly into Herdr or the
[Collie web dashboard](https://github.com/AltanS/collie).

It uses Omarchy's native Quickshell UI and follows your desktop theme, with a
honeycomb icon, compact rows, and a panel that grows only as far as it needs to.

## What you can do

- **Triage agents.** Needs you → Ready · unseen → Working → Recent. Completion
  stays unseen until the backend records it as seen; polling never clears it.
- **Jump to the exact target.** Pick **Collie** or **Herdr** once, then click any
  agent, shell, tab, or workspace. Your destination is saved across restarts.
- **Browse without leaving Swarm.** The **›** beside a workspace or tab opens
  its contents. Clicking the row itself opens that target.
- **Find work quickly.** Filter each view by title, workspace, tab, agent type,
  or working directory. Search includes collapsed Recent entries.
- **Choose an action per item.** Right-click for explicit destinations, browsing
  actions, and copying a dashboard link, working directory, or item ID.
- **Use the keyboard.** Select rows, switch views, open item menus, and navigate
  back without reaching for the mouse.

## Requirements

- **Omarchy with the Quickshell shell and plugin CLI.** This is a native shell
  plugin; Waybar-only setups cannot load it.
- **[Herdr](https://herdr.dev)** running on the desktop, with `herdr` on `PATH`.
- **The session bridge used by the [Collie web dashboard](https://github.com/AltanS/collie)**
  running with Herdr as its backend. Its default address is
  `http://127.0.0.1:8787`.
- **Python 3.9+** and **xdg-open**, available on `PATH`.

Tested locally with Omarchy **4.0.3-1**, Herdr **0.9.0**, and the dashboard bridge
**1.8.0**. Other backend/version combinations have not been verified.

Swarm does not install or start Herdr or the bridge. Follow their upstream setup
instructions first. Confirm the dashboard can see your Herdr sessions before
installing Swarm.

## Install

```sh
omarchy plugin add https://github.com/baileyrosen3/omarchy-swarm.git --yes &&
  bash ~/.config/omarchy/plugins/blr.swarm/check-deps.sh &&
  omarchy plugin enable blr.swarm
```

The plugin ID is **`blr.swarm`**. It installs into
`~/.config/omarchy/plugins/blr.swarm` and appears in the left navbar section.
Click the honeycomb icon to open it. The preflight requires **Collie, Herdr,
Python 3.9+, and xdg-open** before enabling the plugin. It reports missing
programs with download guidance and does not install them automatically.

Swarm also checks the required commands when loading session data, so a missing
dependency produces an actionable message in the popup. Installed commands and
a running, connected bridge are separate requirements.

```sh
# Enable an installed copy
omarchy plugin enable blr.swarm

# Update from this repository
omarchy plugin update blr.swarm --yes

# Remove the plugin
omarchy plugin remove blr.swarm --yes
```

## Using Swarm

| View | Contents |
| --- | --- |
| **Agents** | Attention groups and collapsible Recent, with newest/oldest sorting. |
| **Spaces** | Workspaces, status, tab/pane counts, and access to their contents. |
| **Tabs** | Every tab with workspace context and access to its panes. |
| **Shells** | Shell panes with title, location, and activity context. |

Choose the session in the footer when multiple running sessions are available.
The navbar indicator is red for blocked agents and green for unseen completion.
Long lists scroll; the header and footer stay visible.

### Destinations

| Selection | Herdr terminal | Collie web dashboard |
| --- | --- | --- |
| Agent or shell | Focus the exact pane. | Open that pane's page. |
| Workspace | Focus that workspace. | Open its Space page. |
| Tab | Focus that exact tab. | Open a pane in that tab, preferring its focused pane. |

A tab without an exposed pane falls back to its Space page in the dashboard.
Remote-host items open their scoped dashboard page; local Herdr focus is disabled
for those items. Links and workspace/tab associations retain host and session
identity.

### Right-click actions

Right-click an **item**, or select it and press **Shift+F10**, for:

- **Open in Herdr terminal** or **Open in Collie dashboard**—a one-time override
  that leaves your saved destination unchanged.
- **Browse tabs and panes**, **Browse panes**, or **Show workspace**, as applicable.
- **Copy Collie dashboard link**.
- **Copy working directory**, when the item exposes one.
- **Copy item ID**.

The menu stays attached to the selected item while it is open. Failed navigation
keeps Swarm open and shows the error so you can retry.

### Keyboard and mouse

| Control | Action |
| --- | --- |
| Navbar left click | Open/close Swarm. |
| Navbar middle click | Open the Collie web dashboard. |
| Navbar right click | Cycle running sessions. |
| Item left click / Enter | Open the item in your chosen destination. |
| Item right click / Shift+F10 / Menu key | Open its action menu. |
| Up / Down | Select a row and scroll it into view. |
| › / Right arrow with an empty search | Browse the selected workspace or tab. |
| Tab / Shift+Tab | Move between controls. |
| Escape | Dismiss an item menu, clear search, go back, or close the popup. |
| Ctrl+1 / 2 / 3 / 4 | Agents / Spaces / Tabs / Shells. |
| Ctrl+F | Focus search. |
| Ctrl+D | Switch between Collie and Herdr destinations. |
| Ctrl+R / ↻ | Refresh session data. |
| Ctrl+O / ↗ | Open the Collie web dashboard. |

## Settings

Configure Swarm through the shell's widget settings, or edit its existing entry
in `~/.config/omarchy/shell.json`.

| Setting | Default | Purpose |
| --- | --- | --- |
| `bridgeUrl` | `http://127.0.0.1:8787` | Session snapshot and pane-focus API. |
| `browserUrl` | `http://127.0.0.1:8787` | Dashboard URL; may differ from the bridge, e.g. a tailnet address. |
| `navigationTarget` | `Collie dashboard` | Default row destination; alternatively `Herdr terminal`. |
| `openRefreshSeconds` | `2` | Polling interval while the popup is open. |
| `closedRefreshSeconds` | `10` | Polling interval while closed. |
| `panelWidth` | `400` | Popup width, constrained to the screen. |
| `showAttentionCount` | `true` | Show the navbar attention dot. |

For example, update the existing layout entry to:

```json
{
  "id": "blr.swarm",
  "navigationTarget": "Herdr terminal",
  "panelWidth": 400
}
```

This is one widget entry, not a replacement for the entire shell configuration.
Recent expansion and sort preferences are also saved automatically.

## Troubleshooting

**No data or a disconnected bridge:** open the dashboard and confirm Herdr is
connected. Check `bridgeUrl`, then press **Ctrl+R**. You can inspect the same
read-only snapshot Swarm uses:

```sh
python3 -B ~/.config/omarchy/plugins/blr.swarm/collie.py snapshot http://127.0.0.1:8787
```

**A required program is missing:** install
[Collie](https://github.com/AltanS/collie#quickstart) and
[Herdr](https://herdr.dev), make sure both commands are on `PATH`, then rerun:

```sh
bash ~/.config/omarchy/plugins/blr.swarm/check-deps.sh
```

**Herdr will not focus an item:** confirm `herdr` is on the desktop shell's
`PATH` and that the selected session still exists. Use the right-click menu to
open the item in the dashboard while troubleshooting.

**Changes are not visible:** user plugin files normally hot-reload. If the shell
still shows cached code, run `omarchy restart shell`.

Cached session data is marked explicitly when the bridge fails. Swarm does not
send terminal input, restart your sessions, or mark panes seen during polling.

## Development

```sh
git clone https://github.com/baileyrosen3/omarchy-swarm.git
cd omarchy-swarm

omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Panel.qml SwarmIcon.qml
node tests/model.test.cjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
```

| File | Responsibility |
| --- | --- |
| `Panel.qml` | Navbar widget, popup, item menus, keyboard handling, and process control. |
| `SwarmIcon.qml` | Theme-aware honeycomb icon. |
| `SessionModel.js` | Triage, filtering, scope matching, and dashboard links. |
| `collie.py` | Standard-library bridge adapter and exact Herdr focus operations. |
| `check-deps.sh` | Read-only prerequisite check before enabling the plugin. |
| `manifest.json` | Plugin identity and settings schema. |

Node is only needed for development tests. The runtime has no npm or pip
dependencies. The helper disables inherited HTTP proxies for bridge requests
and invokes Herdr with argument arrays. Tests cover triage, all four views,
search, host collisions, scoped links, and useful failure responses. QML linting
requires Omarchy's local shell imports.

## License

[MIT](LICENSE). Swarm is an independent plugin for Omarchy, Herdr, and the Collie
web dashboard.
