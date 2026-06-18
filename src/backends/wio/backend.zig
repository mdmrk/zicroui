//! Optional wio + fixed-function OpenGL backend for zicroui.
//!
//! zicroui itself is renderer-agnostic: it only emits a command list and asks
//! the host for text metrics. This backend provides a batteries-included
//! implementation of both halves on top of wio's window/GL context plus the
//! bundled microui font/icon atlas, so a host only has to write its UI code.
//!
//! Typical usage:
//!
//!     try backend.init(width, height);
//!     backend.attach(&ctx);            // wires up the text-metric callbacks
//!     // ... per frame:
//!     while (events.pop()) |event| {
//!         if (event == .close) break;
//!         backend.processEvent(&ctx, event);
//!     }
//!     ctx.begin();
//!     // ... build UI ...
//!     ctx.end();
//!     backend.clear(bg);
//!     backend.render(&ctx);
//!     backend.present(&window);

const std = @import("std");
const wio = @import("wio");
const zu = @import("../../zicroui.zig");
const renderer = @import("renderer.zig");

pub const atlas = @import("atlas.zig");

// ---------------------------------------------------------------------------
// Renderer lifecycle (thin re-exports of the GL renderer)
// ---------------------------------------------------------------------------

/// Initialise the GL renderer. A wio GL context must already be current.
pub const init = renderer.init;
/// Notify the renderer of a new framebuffer size (also done by `processEvent`).
pub const setSize = renderer.setSize;
/// Clear the framebuffer to `color`.
pub const clear = renderer.clear;
/// Flush batched geometry and swap buffers.
pub const present = renderer.present;

/// Text-metric callbacks matching the zicroui signatures.
pub const textWidth = renderer.textWidth;
pub const textHeight = renderer.textHeight;

/// Point a context's text-metric callbacks at this backend. Call once after
/// `Context.init`, before the first `begin`.
pub fn attach(ctx: *zu.Context) void {
    ctx.text_width = textWidth;
    ctx.text_height = textHeight;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Walk a finished frame's command list and draw it. Does not clear or
/// present; call `clear` before and `present` after.
pub fn render(ctx: *zu.Context) void {
    var it = ctx.commandIterator();
    while (it.next()) |cmd| switch (cmd) {
        .text => |t| renderer.drawText(t.str, t.pos, t.color),
        .rect => |r| renderer.drawRect(r.rect, r.color),
        .icon => |ic| renderer.drawIcon(@intCast(@intFromEnum(ic.id)), ic.rect, ic.color),
        .clip => |cr| renderer.setClip(cr),
        .jump => {},
    };
}

// ---------------------------------------------------------------------------
// Input translation
// ---------------------------------------------------------------------------

// Last known mouse position; wio button events do not carry a position, so we
// remember it from the most recent mouse-move event.
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;

/// Feed a wio event into the context. Handles mouse, keyboard, text and
/// framebuffer-resize events; all other events (including `.close`) are
/// ignored so the host can act on them itself.
pub fn processEvent(ctx: *zu.Context, event: wio.Event) void {
    switch (event) {
        .size_physical => |s| setSize(s.width, s.height),
        .mouse => |m| {
            mouse_x = m.x;
            mouse_y = m.y;
            ctx.inputMouseMove(m.x, m.y);
        },
        .button_press => |b| handleButton(ctx, b, true),
        .button_release => |b| handleButton(ctx, b, false),
        .char => |c| handleChar(ctx, c),
        .scroll_vertical => |dy| ctx.inputScroll(0, @intFromFloat(dy * -30)),
        else => {},
    }
}

fn handleButton(ctx: *zu.Context, button: wio.Button, down: bool) void {
    const mb: ?zu.MouseButtons = switch (button) {
        .mouse_left => .{ .left = true },
        .mouse_right => .{ .right = true },
        .mouse_middle => .{ .middle = true },
        else => null,
    };
    if (mb) |b| {
        if (down) ctx.inputMouseDown(mouse_x, mouse_y, b) else ctx.inputMouseUp(mouse_x, mouse_y, b);
        return;
    }
    const key: ?zu.Keys = switch (button) {
        .left_shift, .right_shift => .{ .shift = true },
        .left_control, .right_control => .{ .ctrl = true },
        .left_alt, .right_alt => .{ .alt = true },
        .enter, .kp_enter => .{ .enter = true },
        .backspace => .{ .backspace = true },
        else => null,
    };
    if (key) |k| {
        if (down) ctx.inputKeyDown(k) else ctx.inputKeyUp(k);
    }
}

fn handleChar(ctx: *zu.Context, c: u21) void {
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(c, &buf) catch return;
    ctx.inputText(buf[0..n]);
}
