"""Print a polkit rule giving active remote graphical sessions the local defaults.

polkit applies an action's `allow_active` default only to sessions on a local
seat. A Remote Login session falls back to `allow_any`, which denies most
desktop actions outright, with no prompt. This reads every installed action and
emits one rule mapping each action whose two defaults differ to its local
answer, so an active remote session behaves exactly as the console would.

Actions installed after this runs keep the remote default until it runs again.

Run: python3 polkit-remote-as-local.py
"""

import json
import pathlib
import sys
import xml.etree.ElementTree as ET

ACTION_DIRS = (
    pathlib.Path("/usr/share/polkit-1/actions"),
    pathlib.Path("/etc/polkit-1/actions"),
)

# polkit's own default when a <defaults> child is absent.
MISSING = "no"

RULE = """\
// Managed by Ansible (hyperi-developer rdp-server role) -- edits are overwritten.
// Gives an active remote graphical session (GRD Remote Login) the local-session
// default for every action where the two differ. Generated from the installed
// polkit actions.
var rdpLocalDefaults = {mapping};

// SSH sessions are remote and active too, so only wayland/x11 sessions qualify.
function rdpIsGraphical(session) {{
    if (!session) {{
        return false;
    }}
    try {{
        var type = polkit.spawn(["/usr/bin/loginctl", "show-session", session,
                                 "--property=Type", "--value"]).trim();
        return type === "wayland" || type === "x11";
    }} catch (error) {{
        return false;
    }}
}}

polkit.addRule(function(action, subject) {{
    if (subject.local || !subject.active) {{
        return polkit.Result.NOT_HANDLED;
    }}
    var answer = rdpLocalDefaults[action.id];
    if (answer === undefined || !rdpIsGraphical(subject.session)) {{
        return polkit.Result.NOT_HANDLED;
    }}
    return answer;
}});
"""


def local_defaults(policy: pathlib.Path) -> dict[str, str]:
    """Return action id -> allow_active for actions where it differs from allow_any."""
    differing: dict[str, str] = {}
    root = ET.parse(policy).getroot()  # noqa: S314 -- root-owned polkit policy files
    for action in root.iter("action"):
        action_id = action.get("id")
        defaults = action.find("defaults")
        if action_id is None or defaults is None:
            continue
        allow_any = (defaults.findtext("allow_any") or MISSING).strip()
        allow_active = (defaults.findtext("allow_active") or MISSING).strip()
        if allow_active != allow_any:
            differing[action_id] = allow_active
    return differing


def main() -> int:
    """Print the rule to stdout."""
    mapping: dict[str, str] = {}
    for directory in ACTION_DIRS:
        if not directory.is_dir():
            continue
        for policy in sorted(directory.glob("*.policy")):
            try:
                mapping.update(local_defaults(policy))
            except ET.ParseError as err:
                print(f"skipping unparseable {policy}: {err}", file=sys.stderr)
    if not mapping:
        print("no polkit actions found", file=sys.stderr)
        return 1
    rendered = json.dumps(mapping, indent=4, sort_keys=True)
    sys.stdout.write(RULE.format(mapping=rendered))
    return 0


if __name__ == "__main__":
    sys.exit(main())
