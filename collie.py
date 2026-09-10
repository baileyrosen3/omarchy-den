#!/usr/bin/env python3
"""Read and normalize Collie's snapshot without leaking proxy settings into polling."""
import json
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    return 0


def prerequisites():
    missing = [name for name in ("collie", "herdr", "xdg-open") if shutil.which(name) is None]
    if not missing:
        return {"ok": True, "missing": []}
    steps = []
    if "collie" in missing:
        steps.append("Install Collie: https://github.com/AltanS/collie#quickstart")
    if "herdr" in missing:
        steps.append("Install Herdr: https://herdr.dev")
    if "xdg-open" in missing:
        steps.append("Install xdg-utils for xdg-open.")
    return {"ok": False, "missing": missing,
            "error": "Missing required commands: " + ", ".join(missing) + ". " + " ".join(steps) + " Make sure they are on the desktop shell's PATH."}


def url_for(raw, session, endpoint="/api/snapshot"):
    parsed = urllib.parse.urlparse(raw)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return None
    path = parsed.path.rstrip("/") + endpoint
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    if session:
        query.append(("session", session))
    return urllib.parse.urlunparse((parsed.scheme, parsed.netloc, path, "", urllib.parse.urlencode(query), ""))


def bridge_request(bridge, session, endpoint, method="GET"):
    target = url_for(bridge, session, endpoint)
    if not target:
        return None, "Session bridge URL must be a complete http(s) URL."
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(target, method=method, headers={"Accept": "application/json", "Cache-Control": "no-store"})
    try:
        with opener.open(request, timeout=2.5) as response:
            if response.status != 200:
                return None, "Session bridge returned HTTP %s." % response.status
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {"ok": True}, None
    except urllib.error.HTTPError as exc:
        return None, "Session bridge returned HTTP %s." % exc.code
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        return None, "Session bridge is unavailable: %s" % getattr(exc, "reason", exc)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    if command == "check":
        result = prerequisites()
        print(json.dumps(result))
        return 0 if result["ok"] else 1
    bridge = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8787"
    session = sys.argv[3] if len(sys.argv) > 3 else ""
    if command == "focus-pane":
        pane_id = sys.argv[4] if len(sys.argv) > 4 else ""
        if not pane_id:
            return fail("A pane id is required.")
        payload, error = bridge_request(bridge, session, "/api/pane/%s/focus" % urllib.parse.quote(pane_id, safe=""), "POST")
        if error:
            return fail(error)
        if not isinstance(payload, dict) or not payload.get("ok"):
            return fail(payload.get("error", "Herdr could not focus this pane.") if isinstance(payload, dict) else "Invalid focus response.")
        print(json.dumps({"ok": True, "action": "pane-focus"}))
        return 0
    if command in ("focus-workspace", "focus-tab"):
        kind = command.removeprefix("focus-")
        target_id = sys.argv[4] if len(sys.argv) > 4 else ""
        if not target_id or target_id.startswith("-"):
            return fail("A valid %s id is required." % kind)
        args = ["herdr"] + (["--session", session] if session else []) + [kind, "focus", target_id]
        try:
            completed = subprocess.run(args, capture_output=True, text=True, timeout=2.5, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return fail("Herdr is unavailable or did not respond. Try again.")
        if completed.returncode != 0:
            return fail((completed.stderr or completed.stdout or "Herdr could not focus this %s." % kind).strip())
        print(json.dumps({"ok": True, "action": kind + "-focus"}))
        return 0
    if command != "snapshot":
        return fail("Unknown session action.")
    requirements = prerequisites()
    if not requirements["ok"]:
        return fail(requirements["error"])
    payload, error = bridge_request(bridge, session, "/api/snapshot")
    if error:
        return fail(error)

    if not isinstance(payload, dict) or not isinstance(payload.get("agents"), list):
        return fail("Session bridge returned an invalid snapshot.")
    payload["ok"] = True
    print(json.dumps(payload, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
