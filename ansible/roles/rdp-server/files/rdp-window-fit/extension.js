// Refit windows into the work area whenever the screen arrangement changes.
//
// Reconnecting to a Remote Login host at a smaller resolution leaves windows
// jammed against the right and bottom edges. Mutter clamps them just far enough
// to keep a strip on screen and never resizes a normal window, so a 700px-wide
// window on a 1280px-wide session is left showing 75px of itself.
//
// This is deliberately NOT the Window State Manager approach, which is retired
// (hyperi-io/hyperi-developer#39). That extension saved geometry and restored
// it when the screen changed, and on disconnect it repositioned windows onto
// the logical monitor that had just been destroyed, tripping
// meta_window_get_work_area_for_logical_monitor's assertion and aborting
// gnome-shell -- which takes the whole session with it.
//
// Two rules keep this one out of that hole:
//
//   1. It is STATELESS. There is no saved geometry, so there is nothing to
//      restore onto a screen that no longer exists. It only ever reads the
//      CURRENT work area and fits windows into it.
//   2. It does nothing at all while no monitor exists. The disconnect leaves
//      the session with zero logical monitors and a primary index of -1, which
//      is the state that makes the work-area lookup abort, so that state is an
//      early return rather than something to be handled carefully.

import GLib from 'gi://GLib';
import Meta from 'gi://Meta';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Mutter emits monitors-changed more than once for a single transition, and on
// reconnect the work area is not final until the panel and docks have been
// laid out again. Fitting against a half-settled layout would move windows
// twice and land them somewhere nobody asked for.
const SETTLE_MS = 700;

// A window narrower than this is not worth refitting -- dialogs and pickers
// place themselves, and dragging them around is worse than leaving them.
const MIN_INTERESTING = 240;

export default class RdpWindowFitExtension {
    enable() {
        this._settleId = 0;
        this._monitorManager = global.backend.get_monitor_manager();
        this._changedId = this._monitorManager.connect(
            'monitors-changed',
            () => this._scheduleFit(),
        );
    }

    disable() {
        if (this._settleId) {
            GLib.source_remove(this._settleId);
            this._settleId = 0;
        }
        if (this._changedId) {
            this._monitorManager.disconnect(this._changedId);
            this._changedId = 0;
        }
        this._monitorManager = null;
    }

    _scheduleFit() {
        if (this._settleId)
            GLib.source_remove(this._settleId);
        this._settleId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SETTLE_MS, () => {
            this._settleId = 0;
            this._fitAll();
            return GLib.SOURCE_REMOVE;
        });
    }

    _fitAll() {
        // The whole safety argument in one line: no monitor, no work area, no
        // work to do. This is the state a disconnect leaves behind.
        if (Main.layoutManager.monitors.length === 0)
            return;

        for (const actor of global.get_window_actors()) {
            try {
                this._fit(actor.meta_window);
            } catch (e) {
                // One awkward window must not stop the rest being rescued.
                console.warn(`rdp-window-fit: skipped a window: ${e}`);
            }
        }
    }

    _fit(win) {
        if (win.is_override_redirect() || win.minimized)
            return;
        if (win.window_type !== Meta.WindowType.NORMAL)
            return;
        // Maximised, tiled and fullscreen windows already follow the monitor.
        if (win.maximizedHorizontally || win.maximizedVertically || win.fullscreen)
            return;
        if (!win.allows_move())
            return;

        const monitor = win.get_monitor();
        if (monitor < 0 || monitor >= Main.layoutManager.monitors.length)
            return;

        const area = Main.layoutManager.getWorkAreaForMonitor(monitor);
        const rect = win.get_frame_rect();
        if (rect.width < MIN_INTERESTING && rect.height < MIN_INTERESTING)
            return;

        // Shrink only as far as the work area, and only when the window is
        // allowed to resize -- a fixed-size window still gets moved back into
        // view, which is the half that matters for reachability.
        const canResize = win.allows_resize();
        const width = canResize ? Math.min(rect.width, area.width) : rect.width;
        const height = canResize ? Math.min(rect.height, area.height) : rect.height;

        const x = Math.max(area.x, Math.min(rect.x, area.x + area.width - width));
        const y = Math.max(area.y, Math.min(rect.y, area.y + area.height - height));

        if (x === rect.x && y === rect.y && width === rect.width && height === rect.height)
            return;

        win.move_resize_frame(false, x, y, width, height);
    }
}
