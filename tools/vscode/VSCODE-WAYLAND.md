# VS Code Window Sizing Fix for Wayland/4K Displays

## Problem

VS Code on Linux with Wayland may display windows at incorrect sizes (e.g., 1920x1080) even on 4K displays. This occurs because:

1. VS Code runs in XWayland compatibility mode by default
2. Window dimensions from previous displays are cached in `storage.json`
3. When switching windows or monitors, cached dimensions are restored instead of recalculated

## Solution

### One-Time Setup: Enable Native Wayland Support

Edit `~/.config/Code/argv.json` and add the Wayland options:

```json
{
    "disable-hardware-acceleration": true,
    "enable-features": "UseOzonePlatform,WaylandWindowDecorations",
    "ozone-platform-hint": "auto"
}
```

Configure window behavior in `~/.config/Code/User/settings.json`:

```json
{
    "window.newWindowDimensions": "maximized",
    "window.restoreWindows": "all"
}
```

### Clear Cached Window State

Run the remediation script:

```bash
# Close all VSCode windows first, then run:
/projects/hyperi-developer/tools/vscode/vscode-wayland.sh
```

The script:
- Verifies VSCode is not running
- Clears Session Storage and Local Storage directories
- Resets `windowsState` in `storage.json` to maximized mode without cached coordinates

## Manual Remediation

If you prefer to do this manually:

```bash
# 1. Close VSCode completely

# 2. Clear storage directories
rm -rf ~/.config/Code/Session\ Storage
rm -rf ~/.config/Code/Local\ Storage

# 3. Reset window state (requires Python)
python3 << 'EOF'
import json, os
path = os.path.expanduser('~/.config/Code/User/globalStorage/storage.json')
with open(path, 'r') as f: data = json.load(f)
data['windowsState'] = {"lastActiveWindow": {"uiState": {"mode": 1}}, "openedWindows": []}
with open(path, 'w') as f: json.dump(data, f, indent=4)
EOF

# 4. Launch VSCode
```

## Technical Details

The cached window state is stored in:
- `~/.config/Code/User/globalStorage/storage.json` - contains `windowsState` with x, y, width, height
- `~/.config/Code/Session Storage/` - Electron session data
- `~/.config/Code/Local Storage/` - Electron local storage

The `windowsState.lastActiveWindow.uiState.mode` values:
- `0` = normal (uses cached x, y, width, height)
- `1` = maximized (ignores cached dimensions)
- `2` = fullscreen

## References

- [VS Code Issue #210624 - Ubuntu window sizing](https://github.com/microsoft/vscode/issues/210624)
- [VS Code Issue #90650 - Incorrect dimensions after resolution change](https://github.com/microsoft/vscode/issues/90650)
