//! zicroui - a tiny, portable, immediate-mode UI library.
//!
//! Idiomatic Zig port of rxi's microui (https://github.com/rxi/microui).
//! The library produces a list of drawing commands; the host application is
//! responsible for feeding input and rendering the resulting commands.
//!
//! Original C library: Copyright (c) 2024 rxi, MIT licensed (see LICENSE).

const std = @import("std");
const build_options = @import("build_options");

pub const version = "2.02";

/// Optional batteries-included rendering/input backend built on wio and
/// fixed-function OpenGL. Only available when the library is built with the
/// `wio-backend` option enabled; otherwise this is an empty namespace.
pub const backend = if (build_options.wio_backend)
    @import("backends/wio/backend.zig")
else
    struct {};

// Fixed-capacity sizing. The library performs no allocation: everything lives
// inside `Context`.
const rootlist_size = 32;
const containerstack_size = 32;
const clipstack_size = 32;
const idstack_size = 32;
const layoutstack_size = 16;
const containerpool_size = 48;
const treenodepool_size = 48;
const max_widths = 16;
const max_fmt = 127;
const max_commands = 16384;
const text_stack_size = 256 * 1024;
const input_text_size = 32;

const unclipped_rect: Rect = .{ .x = 0, .y = 0, .w = 0x1000000, .h = 0x1000000 };

/// 32-bit FNV-1a initial hash value.
const hash_initial: Id = 2166136261;

const min_real = -0x1000000;

// ===========================================================================
// Core value types
// ===========================================================================

pub const Id = u32;
pub const Real = f32;
/// Opaque font handle, interpreted by the host's text callbacks.
pub const Font = ?*anyopaque;

pub const Vec2 = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
};

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

pub fn vec2(x: i32, y: i32) Vec2 {
    return .{ .x = x, .y = y };
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) Rect {
    return .{ .x = x, .y = y, .w = w, .h = h };
}

pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

// ===========================================================================
// Enums
// ===========================================================================

pub const Clip = enum { none, part, all };

pub const ColorId = enum(u32) {
    text,
    border,
    window_bg,
    title_bg,
    title_text,
    panel_bg,
    button,
    button_hover,
    button_focus,
    base,
    base_hover,
    base_focus,
    scroll_base,
    scroll_thumb,

    fn offset(self: ColorId, n: u32) ColorId {
        return @enumFromInt(@intFromEnum(self) + n);
    }
};

const color_count = @typeInfo(ColorId).@"enum".fields.len;

pub const Icon = enum(i32) {
    none = 0,
    close = 1,
    check,
    collapsed,
    expanded,
};

// ===========================================================================
// Flag sets
// ===========================================================================

/// Result flags returned by controls.
pub const Result = packed struct(u8) {
    active: bool = false,
    submit: bool = false,
    change: bool = false,
    _pad: u5 = 0,

    pub fn any(self: Result) bool {
        return @as(u8, @bitCast(self)) != 0;
    }
};

/// Per-control behaviour options.
pub const Options = packed struct(u16) {
    align_center: bool = false,
    align_right: bool = false,
    no_interact: bool = false,
    no_frame: bool = false,
    no_resize: bool = false,
    no_scroll: bool = false,
    no_close: bool = false,
    no_title: bool = false,
    hold_focus: bool = false,
    auto_size: bool = false,
    popup: bool = false,
    closed: bool = false,
    expanded: bool = false,
    _pad: u3 = 0,

    pub fn merge(a: Options, b: Options) Options {
        return @bitCast(@as(u16, @bitCast(a)) | @as(u16, @bitCast(b)));
    }
};

pub const MouseButtons = packed struct(u8) {
    left: bool = false,
    right: bool = false,
    middle: bool = false,
    _pad: u5 = 0,

    pub fn merge(a: MouseButtons, b: MouseButtons) MouseButtons {
        return @bitCast(@as(u8, @bitCast(a)) | @as(u8, @bitCast(b)));
    }
    pub fn remove(a: MouseButtons, b: MouseButtons) MouseButtons {
        return @bitCast(@as(u8, @bitCast(a)) & ~@as(u8, @bitCast(b)));
    }
    pub fn eql(a: MouseButtons, b: MouseButtons) bool {
        return @as(u8, @bitCast(a)) == @as(u8, @bitCast(b));
    }
    pub fn contains(a: MouseButtons, b: MouseButtons) bool {
        return (@as(u8, @bitCast(a)) & @as(u8, @bitCast(b))) != 0;
    }
    pub fn isEmpty(a: MouseButtons) bool {
        return @as(u8, @bitCast(a)) == 0;
    }
};

pub const Keys = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,
    _pad: u3 = 0,

    pub fn merge(a: Keys, b: Keys) Keys {
        return @bitCast(@as(u8, @bitCast(a)) | @as(u8, @bitCast(b)));
    }
    pub fn remove(a: Keys, b: Keys) Keys {
        return @bitCast(@as(u8, @bitCast(a)) & ~@as(u8, @bitCast(b)));
    }
    pub fn contains(a: Keys, b: Keys) bool {
        return (@as(u8, @bitCast(a)) & @as(u8, @bitCast(b))) != 0;
    }
};

// ===========================================================================
// Commands
// ===========================================================================

pub const RectCommand = struct { rect: Rect, color: Color };
pub const TextCommand = struct { font: Font, pos: Vec2, color: Color, str: []const u8 };
pub const IconCommand = struct { rect: Rect, id: Icon, color: Color };

/// A single drawing command. `jump` is an internal control-flow command used to
/// stitch root containers together in z-order; renderers can ignore it (the
/// `CommandIterator` follows jumps automatically).
pub const Command = union(enum) {
    jump: usize,
    clip: Rect,
    rect: RectCommand,
    text: TextCommand,
    icon: IconCommand,
};

/// Iterates the command list in z-order, transparently following jump commands.
pub const CommandIterator = struct {
    ctx: *Context,
    idx: usize = 0,

    pub fn next(self: *CommandIterator) ?Command {
        while (self.idx < self.ctx.command_count) {
            const cmd = self.ctx.commands[self.idx];
            switch (cmd) {
                .jump => |dst| self.idx = dst,
                else => {
                    self.idx += 1;
                    return cmd;
                },
            }
        }
        return null;
    }
};

// ===========================================================================
// Layout / containers / style
// ===========================================================================

const NextType = enum { none, relative, absolute };

pub const Layout = struct {
    body: Rect = .{},
    next: Rect = .{},
    position: Vec2 = .{},
    size: Vec2 = .{},
    max: Vec2 = .{},
    widths: [max_widths]i32 = [_]i32{0} ** max_widths,
    items: i32 = 0,
    item_index: i32 = 0,
    next_row: i32 = 0,
    next_type: NextType = .none,
    indent: i32 = 0,
};

pub const Container = struct {
    /// Index of this container's head jump command, or null for non-root
    /// containers (panels). Used to identify root containers.
    head: ?usize = null,
    tail: ?usize = null,
    rect: Rect = .{},
    body: Rect = .{},
    content_size: Vec2 = .{},
    scroll: Vec2 = .{},
    zindex: i32 = 0,
    open: bool = false,
};

pub const PoolItem = struct {
    id: Id = 0,
    last_update: i32 = 0,
};

pub const Style = struct {
    font: Font = null,
    size: Vec2 = .{ .x = 68, .y = 10 },
    padding: i32 = 5,
    spacing: i32 = 4,
    indent: i32 = 24,
    title_height: i32 = 24,
    scrollbar_size: i32 = 12,
    thumb_size: i32 = 8,
    colors: [color_count]Color = default_colors,
};

const default_colors = [color_count]Color{
    .{ .r = 230, .g = 230, .b = 230, .a = 255 }, // text
    .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // border
    .{ .r = 50, .g = 50, .b = 50, .a = 255 }, // window_bg
    .{ .r = 25, .g = 25, .b = 25, .a = 255 }, // title_bg
    .{ .r = 240, .g = 240, .b = 240, .a = 255 }, // title_text
    .{ .r = 0, .g = 0, .b = 0, .a = 0 }, // panel_bg
    .{ .r = 75, .g = 75, .b = 75, .a = 255 }, // button
    .{ .r = 95, .g = 95, .b = 95, .a = 255 }, // button_hover
    .{ .r = 115, .g = 115, .b = 115, .a = 255 }, // button_focus
    .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // base
    .{ .r = 35, .g = 35, .b = 35, .a = 255 }, // base_hover
    .{ .r = 40, .g = 40, .b = 40, .a = 255 }, // base_focus
    .{ .r = 43, .g = 43, .b = 43, .a = 255 }, // scroll_base
    .{ .r = 30, .g = 30, .b = 30, .a = 255 }, // scroll_thumb
};

// ===========================================================================
// Generic fixed-capacity stack
// ===========================================================================

fn Stack(comptime T: type, comptime n: usize) type {
    return struct {
        const Self = @This();
        items: [n]T = undefined,
        idx: usize = 0,

        fn push(self: *Self, val: T) void {
            std.debug.assert(self.idx < n);
            self.items[self.idx] = val;
            self.idx += 1;
        }
        fn pop(self: *Self) void {
            std.debug.assert(self.idx > 0);
            self.idx -= 1;
        }
        fn top(self: *Self) *T {
            std.debug.assert(self.idx > 0);
            return &self.items[self.idx - 1];
        }
    };
}

// ===========================================================================
// Context
// ===========================================================================

pub const Context = struct {
    // ----- host callbacks -----
    text_width: ?*const fn (font: Font, str: []const u8) i32 = null,
    text_height: ?*const fn (font: Font) i32 = null,
    draw_frame: *const fn (ctx: *Context, r: Rect, colorid: ColorId) void = defaultDrawFrame,

    // ----- core state -----
    style: Style = .{},
    hover: Id = 0,
    focus: Id = 0,
    last_id: Id = 0,
    last_rect: Rect = .{},
    last_zindex: i32 = 0,
    updated_focus: bool = false,
    frame: i32 = 0,
    hover_root: ?*Container = null,
    next_hover_root: ?*Container = null,
    scroll_target: ?*Container = null,
    number_edit_buf: [max_fmt]u8 = undefined,
    number_edit: Id = 0,

    // ----- command list -----
    commands: [max_commands]Command = undefined,
    command_count: usize = 0,
    text_buf: [text_stack_size]u8 = undefined,
    text_buf_len: usize = 0,

    // ----- stacks -----
    root_list: Stack(*Container, rootlist_size) = .{},
    container_stack: Stack(*Container, containerstack_size) = .{},
    clip_stack: Stack(Rect, clipstack_size) = .{},
    id_stack: Stack(Id, idstack_size) = .{},
    layout_stack: Stack(Layout, layoutstack_size) = .{},

    // ----- retained state pools -----
    container_pool: [containerpool_size]PoolItem = [_]PoolItem{.{}} ** containerpool_size,
    containers: [containerpool_size]Container = [_]Container{.{}} ** containerpool_size,
    treenode_pool: [treenodepool_size]PoolItem = [_]PoolItem{.{}} ** treenodepool_size,

    // ----- input state -----
    mouse_pos: Vec2 = .{},
    last_mouse_pos: Vec2 = .{},
    mouse_delta: Vec2 = .{},
    scroll_delta: Vec2 = .{},
    mouse_down: MouseButtons = .{},
    mouse_pressed: MouseButtons = .{},
    key_down: Keys = .{},
    key_pressed: Keys = .{},
    input_text: [input_text_size]u8 = undefined,

    /// Reset a context to its initial state. The host must then assign
    /// `text_width` and `text_height` before calling `begin`.
    pub fn init(ctx: *Context) void {
        ctx.* = .{};
        ctx.input_text[0] = 0;
    }

    fn col(ctx: *Context, id: ColorId) Color {
        return ctx.style.colors[@intFromEnum(id)];
    }

    // ------------------------------------------------------------------
    // Frame lifecycle
    // ------------------------------------------------------------------

    pub fn begin(ctx: *Context) void {
        std.debug.assert(ctx.text_width != null and ctx.text_height != null);
        ctx.command_count = 0;
        ctx.text_buf_len = 0;
        ctx.root_list.idx = 0;
        ctx.scroll_target = null;
        ctx.hover_root = ctx.next_hover_root;
        ctx.next_hover_root = null;
        ctx.mouse_delta.x = ctx.mouse_pos.x - ctx.last_mouse_pos.x;
        ctx.mouse_delta.y = ctx.mouse_pos.y - ctx.last_mouse_pos.y;
        ctx.frame += 1;
    }

    pub fn end(ctx: *Context) void {
        // Stacks must be balanced.
        std.debug.assert(ctx.container_stack.idx == 0);
        std.debug.assert(ctx.clip_stack.idx == 0);
        std.debug.assert(ctx.id_stack.idx == 0);
        std.debug.assert(ctx.layout_stack.idx == 0);

        // Handle scroll input.
        if (ctx.scroll_target) |st| {
            st.scroll.x += ctx.scroll_delta.x;
            st.scroll.y += ctx.scroll_delta.y;
        }

        // Unset focus if its id was not touched this frame.
        if (!ctx.updated_focus) ctx.focus = 0;
        ctx.updated_focus = false;

        // Bring hover root to front if the mouse was pressed.
        if (ctx.next_hover_root) |nhr| {
            if (!ctx.mouse_pressed.isEmpty() and nhr.zindex < ctx.last_zindex and nhr.zindex >= 0) {
                ctx.bringToFront(nhr);
            }
        }

        // Reset input state.
        ctx.key_pressed = .{};
        ctx.input_text[0] = 0;
        ctx.mouse_pressed = .{};
        ctx.scroll_delta = .{};
        ctx.last_mouse_pos = ctx.mouse_pos;

        // Sort root containers by zindex.
        const n = ctx.root_list.idx;
        std.sort.pdq(*Container, ctx.root_list.items[0..n], {}, cmpZindex);

        // Set root container jump commands.
        for (0..n) |i| {
            const cnt = ctx.root_list.items[i];
            if (i == 0) {
                // Make the first command jump to the first container.
                ctx.commands[0] = .{ .jump = cnt.head.? + 1 };
            } else {
                const prev = ctx.root_list.items[i - 1];
                ctx.commands[prev.tail.?] = .{ .jump = cnt.head.? + 1 };
            }
            if (i == n - 1) {
                ctx.commands[cnt.tail.?] = .{ .jump = ctx.command_count };
            }
        }
    }

    fn cmpZindex(_: void, a: *Container, b: *Container) bool {
        return a.zindex < b.zindex;
    }

    pub fn setFocus(ctx: *Context, id: Id) void {
        ctx.focus = id;
        ctx.updated_focus = true;
    }

    // ------------------------------------------------------------------
    // Id management
    // ------------------------------------------------------------------

    pub fn getId(ctx: *Context, data: []const u8) Id {
        const idx = ctx.id_stack.idx;
        var res: Id = if (idx > 0) ctx.id_stack.items[idx - 1] else hash_initial;
        hash(&res, data);
        ctx.last_id = res;
        return res;
    }

    pub fn pushId(ctx: *Context, data: []const u8) void {
        ctx.id_stack.push(ctx.getId(data));
    }

    pub fn popId(ctx: *Context) void {
        ctx.id_stack.pop();
    }

    // ------------------------------------------------------------------
    // Clipping
    // ------------------------------------------------------------------

    pub fn pushClipRect(ctx: *Context, r: Rect) void {
        const last = ctx.getClipRect();
        ctx.clip_stack.push(intersectRects(r, last));
    }

    pub fn popClipRect(ctx: *Context) void {
        ctx.clip_stack.pop();
    }

    pub fn getClipRect(ctx: *Context) Rect {
        std.debug.assert(ctx.clip_stack.idx > 0);
        return ctx.clip_stack.top().*;
    }

    pub fn checkClip(ctx: *Context, r: Rect) Clip {
        const cr = ctx.getClipRect();
        if (r.x > cr.x + cr.w or r.x + r.w < cr.x or
            r.y > cr.y + cr.h or r.y + r.h < cr.y) return .all;
        if (r.x >= cr.x and r.x + r.w <= cr.x + cr.w and
            r.y >= cr.y and r.y + r.h <= cr.y + cr.h) return .none;
        return .part;
    }

    // ------------------------------------------------------------------
    // Containers
    // ------------------------------------------------------------------

    pub fn getCurrentContainer(ctx: *Context) *Container {
        return ctx.container_stack.top().*;
    }

    fn getContainerImpl(ctx: *Context, id: Id, opt: Options) ?*Container {
        // Try to fetch an existing container from the pool.
        if (poolGet(&ctx.container_pool, id)) |idx| {
            if (ctx.containers[idx].open or !opt.closed) {
                poolUpdate(ctx, &ctx.container_pool, idx);
            }
            return &ctx.containers[idx];
        }
        if (opt.closed) return null;
        // Not found: initialise a new container.
        const idx = poolInit(ctx, &ctx.container_pool, id);
        const cnt = &ctx.containers[idx];
        cnt.* = .{};
        cnt.open = true;
        ctx.bringToFront(cnt);
        return cnt;
    }

    pub fn getContainer(ctx: *Context, name: []const u8) *Container {
        const id = ctx.getId(name);
        return ctx.getContainerImpl(id, .{}).?;
    }

    pub fn bringToFront(ctx: *Context, cnt: *Container) void {
        ctx.last_zindex += 1;
        cnt.zindex = ctx.last_zindex;
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------

    pub fn inputMouseMove(ctx: *Context, x: i32, y: i32) void {
        ctx.mouse_pos = .{ .x = x, .y = y };
    }

    pub fn inputMouseDown(ctx: *Context, x: i32, y: i32, btn: MouseButtons) void {
        ctx.inputMouseMove(x, y);
        ctx.mouse_down = ctx.mouse_down.merge(btn);
        ctx.mouse_pressed = ctx.mouse_pressed.merge(btn);
    }

    pub fn inputMouseUp(ctx: *Context, x: i32, y: i32, btn: MouseButtons) void {
        ctx.inputMouseMove(x, y);
        ctx.mouse_down = ctx.mouse_down.remove(btn);
    }

    pub fn inputScroll(ctx: *Context, x: i32, y: i32) void {
        ctx.scroll_delta.x += x;
        ctx.scroll_delta.y += y;
    }

    pub fn inputKeyDown(ctx: *Context, key: Keys) void {
        ctx.key_pressed = ctx.key_pressed.merge(key);
        ctx.key_down = ctx.key_down.merge(key);
    }

    pub fn inputKeyUp(ctx: *Context, key: Keys) void {
        ctx.key_down = ctx.key_down.remove(key);
    }

    pub fn inputText(ctx: *Context, text_in: []const u8) void {
        const len = cstrLen(&ctx.input_text);
        std.debug.assert(len + text_in.len + 1 <= input_text_size);
        @memcpy(ctx.input_text[len .. len + text_in.len], text_in);
        ctx.input_text[len + text_in.len] = 0;
    }

    // ------------------------------------------------------------------
    // Command list
    // ------------------------------------------------------------------

    fn pushCommand(ctx: *Context, cmd: Command) usize {
        const idx = ctx.command_count;
        std.debug.assert(idx < max_commands);
        ctx.commands[idx] = cmd;
        ctx.command_count += 1;
        return idx;
    }

    /// Returns an iterator over the frame's drawing commands, in z-order.
    pub fn commandIterator(ctx: *Context) CommandIterator {
        return .{ .ctx = ctx };
    }

    fn pushJump(ctx: *Context, dst: ?usize) usize {
        return ctx.pushCommand(.{ .jump = dst orelse 0 });
    }

    pub fn setClip(ctx: *Context, r: Rect) void {
        _ = ctx.pushCommand(.{ .clip = r });
    }

    pub fn drawRect(ctx: *Context, r: Rect, clr: Color) void {
        const clipped = intersectRects(r, ctx.getClipRect());
        if (clipped.w > 0 and clipped.h > 0) {
            _ = ctx.pushCommand(.{ .rect = .{ .rect = clipped, .color = clr } });
        }
    }

    pub fn drawBox(ctx: *Context, r: Rect, clr: Color) void {
        ctx.drawRect(rect(r.x + 1, r.y, r.w - 2, 1), clr);
        ctx.drawRect(rect(r.x + 1, r.y + r.h - 1, r.w - 2, 1), clr);
        ctx.drawRect(rect(r.x, r.y, 1, r.h), clr);
        ctx.drawRect(rect(r.x + r.w - 1, r.y, 1, r.h), clr);
    }

    pub fn drawText(ctx: *Context, font: Font, str: []const u8, pos: Vec2, clr: Color) void {
        const r = rect(pos.x, pos.y, ctx.text_width.?(font, str), ctx.text_height.?(font));
        const clipped = ctx.checkClip(r);
        if (clipped == .all) return;
        if (clipped == .part) ctx.setClip(ctx.getClipRect());
        // Copy the string into the per-frame text arena.
        const start = ctx.text_buf_len;
        std.debug.assert(start + str.len <= text_stack_size);
        @memcpy(ctx.text_buf[start .. start + str.len], str);
        ctx.text_buf_len += str.len;
        const stored = ctx.text_buf[start .. start + str.len];
        _ = ctx.pushCommand(.{ .text = .{ .font = font, .pos = pos, .color = clr, .str = stored } });
        if (clipped != .none) ctx.setClip(unclipped_rect);
    }

    pub fn drawIcon(ctx: *Context, id: Icon, r: Rect, clr: Color) void {
        const clipped = ctx.checkClip(r);
        if (clipped == .all) return;
        if (clipped == .part) ctx.setClip(ctx.getClipRect());
        _ = ctx.pushCommand(.{ .icon = .{ .id = id, .rect = r, .color = clr } });
        if (clipped != .none) ctx.setClip(unclipped_rect);
    }

    // ------------------------------------------------------------------
    // Layout
    // ------------------------------------------------------------------

    fn getLayout(ctx: *Context) *Layout {
        return ctx.layout_stack.top();
    }

    fn pushLayout(ctx: *Context, body: Rect, scroll: Vec2) void {
        var layout: Layout = .{};
        layout.body = rect(body.x - scroll.x, body.y - scroll.y, body.w, body.h);
        layout.max = .{ .x = min_real, .y = min_real };
        ctx.layout_stack.push(layout);
        var width = [_]i32{0};
        ctx.layoutRow(&width, 0);
    }

    pub fn layoutBeginColumn(ctx: *Context) void {
        ctx.pushLayout(ctx.layoutNext(), vec2(0, 0));
    }

    pub fn layoutEndColumn(ctx: *Context) void {
        const b = ctx.getLayout().*;
        ctx.layout_stack.pop();
        // Inherit position/next_row/max from the child layout where greater.
        const a = ctx.getLayout();
        a.position.x = @max(a.position.x, b.position.x + b.body.x - a.body.x);
        a.next_row = @max(a.next_row, b.next_row + b.body.y - a.body.y);
        a.max.x = @max(a.max.x, b.max.x);
        a.max.y = @max(a.max.y, b.max.y);
    }

    fn layoutRowImpl(ctx: *Context, items: i32, widths: ?[]const i32, height: i32) void {
        const layout = ctx.getLayout();
        if (widths) |w| {
            std.debug.assert(items <= max_widths);
            for (w, 0..) |val, i| layout.widths[i] = val;
        }
        layout.items = items;
        layout.position = .{ .x = layout.indent, .y = layout.next_row };
        layout.size.y = height;
        layout.item_index = 0;
    }

    pub fn layoutRow(ctx: *Context, widths: []const i32, height: i32) void {
        ctx.layoutRowImpl(@intCast(widths.len), widths, height);
    }

    pub fn layoutWidth(ctx: *Context, width: i32) void {
        ctx.getLayout().size.x = width;
    }

    pub fn layoutHeight(ctx: *Context, height: i32) void {
        ctx.getLayout().size.y = height;
    }

    pub fn layoutSetNext(ctx: *Context, r: Rect, relative: bool) void {
        const layout = ctx.getLayout();
        layout.next = r;
        layout.next_type = if (relative) .relative else .absolute;
    }

    pub fn layoutNext(ctx: *Context) Rect {
        const layout = ctx.getLayout();
        const style = &ctx.style;
        var res: Rect = .{};

        if (layout.next_type != .none) {
            // Rect set by layoutSetNext.
            const t = layout.next_type;
            layout.next_type = .none;
            res = layout.next;
            if (t == .absolute) {
                ctx.last_rect = res;
                return res;
            }
        } else {
            // Handle next row.
            if (layout.item_index == layout.items) {
                ctx.layoutRowImpl(layout.items, null, layout.size.y);
            }

            res.x = layout.position.x;
            res.y = layout.position.y;
            res.w = if (layout.items > 0) layout.widths[@intCast(layout.item_index)] else layout.size.x;
            res.h = layout.size.y;
            if (res.w == 0) res.w = style.size.x + style.padding * 2;
            if (res.h == 0) res.h = style.size.y + style.padding * 2;
            if (res.w < 0) res.w += layout.body.w - res.x + 1;
            if (res.h < 0) res.h += layout.body.h - res.y + 1;

            layout.item_index += 1;
        }

        // Update position.
        layout.position.x += res.w + style.spacing;
        layout.next_row = @max(layout.next_row, res.y + res.h + style.spacing);

        // Apply body offset.
        res.x += layout.body.x;
        res.y += layout.body.y;

        // Update max position.
        layout.max.x = @max(layout.max.x, res.x + res.w);
        layout.max.y = @max(layout.max.y, res.y + res.h);

        ctx.last_rect = res;
        return res;
    }

    // ------------------------------------------------------------------
    // Control helpers
    // ------------------------------------------------------------------

    fn inHoverRoot(ctx: *Context) bool {
        var i = ctx.container_stack.idx;
        while (i > 0) {
            i -= 1;
            const item = ctx.container_stack.items[i];
            if (ctx.hover_root) |hr| {
                if (item == hr) return true;
            }
            // Only root containers have `head` set; stop at the current root.
            if (item.head != null) break;
        }
        return false;
    }

    pub fn drawControlFrame(ctx: *Context, id: Id, r: Rect, colorid: ColorId, opt: Options) void {
        if (opt.no_frame) return;
        const cid = if (ctx.focus == id)
            colorid.offset(2)
        else if (ctx.hover == id)
            colorid.offset(1)
        else
            colorid;
        ctx.draw_frame(ctx, r, cid);
    }

    pub fn drawControlText(ctx: *Context, str: []const u8, r: Rect, colorid: ColorId, opt: Options) void {
        const font = ctx.style.font;
        const tw = ctx.text_width.?(font, str);
        ctx.pushClipRect(r);
        const pos_y = r.y + @divTrunc(r.h - ctx.text_height.?(font), 2);
        const pos_x = if (opt.align_center)
            r.x + @divTrunc(r.w - tw, 2)
        else if (opt.align_right)
            r.x + r.w - tw - ctx.style.padding
        else
            r.x + ctx.style.padding;
        ctx.drawText(font, str, vec2(pos_x, pos_y), ctx.col(colorid));
        ctx.popClipRect();
    }

    pub fn mouseOver(ctx: *Context, r: Rect) bool {
        return rectOverlapsVec2(r, ctx.mouse_pos) and
            rectOverlapsVec2(ctx.getClipRect(), ctx.mouse_pos) and
            ctx.inHoverRoot();
    }

    pub fn updateControl(ctx: *Context, id: Id, r: Rect, opt: Options) void {
        const mouseover = ctx.mouseOver(r);

        if (ctx.focus == id) ctx.updated_focus = true;
        if (opt.no_interact) return;
        if (mouseover and ctx.mouse_down.isEmpty()) ctx.hover = id;

        if (ctx.focus == id) {
            if (!ctx.mouse_pressed.isEmpty() and !mouseover) ctx.setFocus(0);
            if (ctx.mouse_down.isEmpty() and !opt.hold_focus) ctx.setFocus(0);
        }

        if (ctx.hover == id) {
            if (!ctx.mouse_pressed.isEmpty()) {
                ctx.setFocus(id);
            } else if (!mouseover) {
                ctx.hover = 0;
            }
        }
    }

    // ------------------------------------------------------------------
    // Controls
    // ------------------------------------------------------------------

    pub fn text(ctx: *Context, txt: []const u8) void {
        const font = ctx.style.font;
        const clr = ctx.col(.text);
        ctx.layoutBeginColumn();
        var widths = [_]i32{-1};
        ctx.layoutRow(&widths, ctx.text_height.?(font));
        var p: usize = 0;
        var line_end: usize = 0;
        while (true) {
            const r = ctx.layoutNext();
            var w: i32 = 0;
            const start = p;
            line_end = p;
            while (true) {
                const word = p;
                while (charAt(txt, p) != 0 and charAt(txt, p) != ' ' and charAt(txt, p) != '\n') p += 1;
                w += ctx.text_width.?(font, txt[word..p]);
                if (w > r.w and line_end != start) break;
                if (p < txt.len) w += ctx.text_width.?(font, txt[p .. p + 1]);
                line_end = p;
                p += 1;
                if (!(charAt(txt, line_end) != 0 and charAt(txt, line_end) != '\n')) break;
            }
            ctx.drawText(font, txt[start..line_end], vec2(r.x, r.y), clr);
            p = line_end + 1;
            if (charAt(txt, line_end) == 0) break;
        }
        ctx.layoutEndColumn();
    }

    pub fn label(ctx: *Context, txt: []const u8) void {
        ctx.drawControlText(txt, ctx.layoutNext(), .text, .{});
    }

    pub fn button(ctx: *Context, txt: []const u8) Result {
        return ctx.buttonEx(txt, .none, .{ .align_center = true });
    }

    pub fn buttonEx(ctx: *Context, label_text: ?[]const u8, icon: Icon, opt: Options) Result {
        var res: Result = .{};
        const id = if (label_text) |l|
            ctx.getId(l)
        else blk: {
            const ic: i32 = @intFromEnum(icon);
            break :blk ctx.getId(std.mem.asBytes(&ic));
        };
        const r = ctx.layoutNext();
        ctx.updateControl(id, r, opt);
        // Handle click.
        if (ctx.mouse_pressed.eql(.{ .left = true }) and ctx.focus == id) {
            res.submit = true;
        }
        // Draw.
        ctx.drawControlFrame(id, r, .button, opt);
        if (label_text) |l| ctx.drawControlText(l, r, .text, opt);
        if (icon != .none) ctx.drawIcon(icon, r, ctx.col(.text));
        return res;
    }

    pub fn checkbox(ctx: *Context, label_text: []const u8, state: *bool) Result {
        var res: Result = .{};
        const id = ctx.getId(std.mem.asBytes(&state));
        var r = ctx.layoutNext();
        const box = rect(r.x, r.y, r.h, r.h);
        ctx.updateControl(id, r, .{});
        // Handle click.
        if (ctx.mouse_pressed.eql(.{ .left = true }) and ctx.focus == id) {
            res.change = true;
            state.* = !state.*;
        }
        // Draw.
        ctx.drawControlFrame(id, box, .base, .{});
        if (state.*) {
            ctx.drawIcon(.check, box, ctx.col(.text));
        }
        r = rect(r.x + box.w, r.y, r.w - box.w, r.h);
        ctx.drawControlText(label_text, r, .text, .{});
        return res;
    }

    pub fn textboxRaw(ctx: *Context, buf: []u8, id: Id, r: Rect, opt: Options) Result {
        var res: Result = .{};
        ctx.updateControl(id, r, opt.merge(.{ .hold_focus = true }));

        if (ctx.focus == id) {
            // Handle text input.
            var len = cstrLen(buf);
            const in = ctx.inputTextStr();
            const n: usize = @min(buf.len - len - 1, in.len);
            if (n > 0) {
                @memcpy(buf[len .. len + n], in[0..n]);
                len += n;
                buf[len] = 0;
                res.change = true;
            }
            // Handle backspace.
            if (ctx.key_pressed.contains(.{ .backspace = true }) and len > 0) {
                // Skip utf-8 continuation bytes.
                len -= 1;
                while (len > 0 and (buf[len] & 0xc0) == 0x80) len -= 1;
                buf[len] = 0;
                res.change = true;
            }
            // Handle return.
            if (ctx.key_pressed.contains(.{ .enter = true })) {
                ctx.setFocus(0);
                res.submit = true;
            }
        }

        // Draw.
        ctx.drawControlFrame(id, r, .base, opt);
        if (ctx.focus == id) {
            const clr = ctx.col(.text);
            const font = ctx.style.font;
            const buf_str = cstr(buf);
            const textw = ctx.text_width.?(font, buf_str);
            const texth = ctx.text_height.?(font);
            const ofx = r.w - ctx.style.padding - textw - 1;
            const textx = r.x + @min(ofx, ctx.style.padding);
            const texty = r.y + @divTrunc(r.h - texth, 2);
            ctx.pushClipRect(r);
            ctx.drawText(font, buf_str, vec2(textx, texty), clr);
            ctx.drawRect(rect(textx + textw, texty, 1, texth), clr);
            ctx.popClipRect();
        } else {
            ctx.drawControlText(cstr(buf), r, .text, opt);
        }

        return res;
    }

    pub fn textbox(ctx: *Context, buf: []u8) Result {
        return ctx.textboxEx(buf, .{});
    }

    pub fn textboxEx(ctx: *Context, buf: []u8, opt: Options) Result {
        const id = ctx.getId(std.mem.asBytes(&buf.ptr));
        const r = ctx.layoutNext();
        return ctx.textboxRaw(buf, id, r, opt);
    }

    fn numberTextbox(ctx: *Context, value: *Real, r: Rect, id: Id) bool {
        if (ctx.mouse_pressed.eql(.{ .left = true }) and ctx.key_down.contains(.{ .shift = true }) and
            ctx.hover == id)
        {
            ctx.number_edit = id;
            const s = std.fmt.bufPrint(&ctx.number_edit_buf, "{d}", .{value.*}) catch ctx.number_edit_buf[0..0];
            ctx.number_edit_buf[s.len] = 0;
        }
        if (ctx.number_edit == id) {
            const res = ctx.textboxRaw(&ctx.number_edit_buf, id, r, .{});
            if (res.submit or ctx.focus != id) {
                value.* = std.fmt.parseFloat(Real, std.mem.trim(u8, cstr(&ctx.number_edit_buf), " ")) catch value.*;
                ctx.number_edit = 0;
            } else {
                return true;
            }
        }
        return false;
    }

    pub fn slider(ctx: *Context, value: *Real, low: Real, high: Real) Result {
        return ctx.sliderEx(value, low, high, 0, 2, .{ .align_center = true });
    }

    pub fn sliderEx(ctx: *Context, value: *Real, low: Real, high: Real, step: Real, decimals: usize, opt: Options) Result {
        var buf: [max_fmt + 1]u8 = undefined;
        var res: Result = .{};
        const last = value.*;
        var v = last;
        const id = ctx.getId(std.mem.asBytes(&value));
        const base = ctx.layoutNext();

        // Handle text input mode.
        if (ctx.numberTextbox(&v, base, id)) return res;

        // Handle normal mode.
        ctx.updateControl(id, base, opt);

        // Handle input.
        if (ctx.focus == id and (ctx.mouse_down.merge(ctx.mouse_pressed)).eql(.{ .left = true })) {
            v = low + toF(ctx.mouse_pos.x - base.x) * (high - low) / toF(base.w);
            if (step != 0) v = @floor((v + step / 2) / step) * step;
        }
        // Clamp and store value, update res.
        v = std.math.clamp(v, low, high);
        value.* = v;
        if (last != v) res.change = true;

        // Draw base.
        ctx.drawControlFrame(id, base, .base, opt);
        // Draw thumb.
        const w = ctx.style.thumb_size;
        const x = toI((v - low) * toF(base.w - w) / (high - low));
        const thumb = rect(base.x + x, base.y, w, base.h);
        ctx.drawControlFrame(id, thumb, .button, opt);
        // Draw text.
        const s = fmtReal(&buf, v, decimals);
        ctx.drawControlText(s, base, .text, opt);

        return res;
    }

    pub fn number(ctx: *Context, value: *Real, step: Real) Result {
        return ctx.numberEx(value, step, 2, .{ .align_center = true });
    }

    pub fn numberEx(ctx: *Context, value: *Real, step: Real, decimals: usize, opt: Options) Result {
        var buf: [max_fmt + 1]u8 = undefined;
        var res: Result = .{};
        const id = ctx.getId(std.mem.asBytes(&value));
        const base = ctx.layoutNext();
        const last = value.*;

        // Handle text input mode.
        if (ctx.numberTextbox(value, base, id)) return res;

        // Handle normal mode.
        ctx.updateControl(id, base, opt);

        // Handle input.
        if (ctx.focus == id and ctx.mouse_down.eql(.{ .left = true })) {
            value.* += toF(ctx.mouse_delta.x) * step;
        }
        // Set flag if value changed.
        if (value.* != last) res.change = true;

        // Draw base.
        ctx.drawControlFrame(id, base, .base, opt);
        // Draw text.
        const s = fmtReal(&buf, value.*, decimals);
        ctx.drawControlText(s, base, .text, opt);

        return res;
    }

    fn headerImpl(ctx: *Context, label_text: []const u8, is_treenode: bool, opt: Options) Result {
        const id = ctx.getId(label_text);
        const idx = poolGet(&ctx.treenode_pool, id);
        var widths = [_]i32{-1};
        ctx.layoutRow(&widths, 0);

        var active = (idx != null);
        const expanded = if (opt.expanded) !active else active;
        const r = ctx.layoutNext();
        ctx.updateControl(id, r, .{});

        // Handle click (toggle expanded state).
        if (ctx.mouse_pressed.eql(.{ .left = true }) and ctx.focus == id) {
            active = !active;
        }

        // Update pool ref.
        if (idx) |i| {
            if (active) {
                poolUpdate(ctx, &ctx.treenode_pool, i);
            } else {
                ctx.treenode_pool[i] = .{};
            }
        } else if (active) {
            _ = poolInit(ctx, &ctx.treenode_pool, id);
        }

        // Draw.
        if (is_treenode) {
            if (ctx.hover == id) ctx.draw_frame(ctx, r, .button_hover);
        } else {
            ctx.drawControlFrame(id, r, .button, .{});
        }
        ctx.drawIcon(
            if (expanded) .expanded else .collapsed,
            rect(r.x, r.y, r.h, r.h),
            ctx.col(.text),
        );
        var tr = r;
        tr.x += r.h - ctx.style.padding;
        tr.w -= r.h - ctx.style.padding;
        ctx.drawControlText(label_text, tr, .text, .{});

        return .{ .active = expanded };
    }

    pub fn header(ctx: *Context, label_text: []const u8) Result {
        return ctx.headerImpl(label_text, false, .{});
    }

    pub fn headerEx(ctx: *Context, label_text: []const u8, opt: Options) Result {
        return ctx.headerImpl(label_text, false, opt);
    }

    pub fn beginTreenode(ctx: *Context, label_text: []const u8) Result {
        return ctx.beginTreenodeEx(label_text, .{});
    }

    pub fn beginTreenodeEx(ctx: *Context, label_text: []const u8, opt: Options) Result {
        const res = ctx.headerImpl(label_text, true, opt);
        if (res.active) {
            ctx.getLayout().indent += ctx.style.indent;
            ctx.id_stack.push(ctx.last_id);
        }
        return res;
    }

    pub fn endTreenode(ctx: *Context) void {
        ctx.getLayout().indent -= ctx.style.indent;
        ctx.popId();
    }

    // ------------------------------------------------------------------
    // Scrollbars / container bodies
    // ------------------------------------------------------------------

    fn scrollbar(ctx: *Context, cnt: *Container, body: *Rect, cs: Vec2, comptime vert: bool) void {
        const main = if (vert) "y" else "x";
        const cross = if (vert) "x" else "y";
        const main_sz = if (vert) "h" else "w";
        const cross_sz = if (vert) "w" else "h";

        // Only add a scrollbar if content size exceeds the body.
        const maxscroll = @field(cs, main) - @field(body.*, main_sz);
        if (maxscroll > 0 and @field(body.*, main_sz) > 0) {
            const id = ctx.getId(if (vert) "!scrollbary" else "!scrollbarx");

            // Sizing / positioning.
            var base = body.*;
            @field(base, cross) = @field(body.*, cross) + @field(body.*, cross_sz);
            @field(base, cross_sz) = ctx.style.scrollbar_size;

            // Handle input.
            ctx.updateControl(id, base, .{});
            if (ctx.focus == id and ctx.mouse_down.eql(.{ .left = true })) {
                @field(cnt.scroll, main) += @divTrunc(@field(ctx.mouse_delta, main) * @field(cs, main), @field(base, main_sz));
            }
            // Clamp scroll to limits.
            @field(cnt.scroll, main) = std.math.clamp(@field(cnt.scroll, main), 0, maxscroll);

            // Draw base and thumb.
            ctx.draw_frame(ctx, base, .scroll_base);
            var thumb = base;
            @field(thumb, main_sz) = @max(ctx.style.thumb_size, @divTrunc(@field(base, main_sz) * @field(body.*, main_sz), @field(cs, main)));
            @field(thumb, main) += @divTrunc(@field(cnt.scroll, main) * (@field(base, main_sz) - @field(thumb, main_sz)), maxscroll);
            ctx.draw_frame(ctx, thumb, .scroll_thumb);

            // Set as scroll target if the mouse is over the body.
            if (ctx.mouseOver(body.*)) ctx.scroll_target = cnt;
        } else {
            @field(cnt.scroll, main) = 0;
        }
    }

    fn scrollbars(ctx: *Context, cnt: *Container, body: *Rect) void {
        const sz = ctx.style.scrollbar_size;
        var cs = cnt.content_size;
        cs.x += ctx.style.padding * 2;
        cs.y += ctx.style.padding * 2;
        ctx.pushClipRect(body.*);
        // Resize body to make room for scrollbars.
        if (cs.y > cnt.body.h) body.w -= sz;
        if (cs.x > cnt.body.w) body.h -= sz;
        ctx.scrollbar(cnt, body, cs, true);
        ctx.scrollbar(cnt, body, cs, false);
        ctx.popClipRect();
    }

    fn pushContainerBody(ctx: *Context, cnt: *Container, body_in: Rect, opt: Options) void {
        var body = body_in;
        if (!opt.no_scroll) ctx.scrollbars(cnt, &body);
        ctx.pushLayout(expandRect(body, -ctx.style.padding), cnt.scroll);
        cnt.body = body;
    }

    fn beginRootContainer(ctx: *Context, cnt: *Container) void {
        ctx.container_stack.push(cnt);
        // Push container to the roots list and push the head command.
        ctx.root_list.push(cnt);
        cnt.head = ctx.pushJump(null);
        // Set as hover root if mouse overlaps and zindex is higher than current.
        if (rectOverlapsVec2(cnt.rect, ctx.mouse_pos) and
            (ctx.next_hover_root == null or cnt.zindex > ctx.next_hover_root.?.zindex))
        {
            ctx.next_hover_root = cnt;
        }
        // Reset clipping so an inner root container is not clipped to an outer.
        ctx.clip_stack.push(unclipped_rect);
    }

    fn endRootContainer(ctx: *Context) void {
        // Push tail jump and patch head; finalised in end().
        const cnt = ctx.getCurrentContainer();
        cnt.tail = ctx.pushJump(null);
        ctx.commands[cnt.head.?] = .{ .jump = ctx.command_count };
        ctx.popClipRect();
        ctx.popContainer();
    }

    fn popContainer(ctx: *Context) void {
        const cnt = ctx.getCurrentContainer();
        const layout = ctx.getLayout();
        cnt.content_size.x = layout.max.x - layout.body.x;
        cnt.content_size.y = layout.max.y - layout.body.y;
        ctx.container_stack.pop();
        ctx.layout_stack.pop();
        ctx.popId();
    }

    // ------------------------------------------------------------------
    // Windows / panels / popups
    // ------------------------------------------------------------------

    pub fn beginWindow(ctx: *Context, title: []const u8, r: Rect) Result {
        return ctx.beginWindowEx(title, r, .{});
    }

    pub fn beginWindowEx(ctx: *Context, title: []const u8, rect_in: Rect, opt: Options) Result {
        const id = ctx.getId(title);
        const cnt = ctx.getContainerImpl(id, opt) orelse return .{};
        if (!cnt.open) return .{};
        ctx.id_stack.push(id);

        if (cnt.rect.w == 0) cnt.rect = rect_in;
        ctx.beginRootContainer(cnt);
        var body = cnt.rect;
        const r = cnt.rect;

        // Draw frame.
        if (!opt.no_frame) {
            ctx.draw_frame(ctx, r, .window_bg);
        }

        // Title bar.
        if (!opt.no_title) {
            var tr = r;
            tr.h = ctx.style.title_height;
            ctx.draw_frame(ctx, tr, .title_bg);

            // Title text.
            {
                const title_id = ctx.getId("!title");
                ctx.updateControl(title_id, tr, opt);
                ctx.drawControlText(title, tr, .title_text, opt);
                if (title_id == ctx.focus and ctx.mouse_down.eql(.{ .left = true })) {
                    cnt.rect.x += ctx.mouse_delta.x;
                    cnt.rect.y += ctx.mouse_delta.y;
                }
                body.y += tr.h;
                body.h -= tr.h;
            }

            // Close button.
            if (!opt.no_close) {
                const close_id = ctx.getId("!close");
                const cr = rect(tr.x + tr.w - tr.h, tr.y, tr.h, tr.h);
                tr.w -= cr.w;
                ctx.drawIcon(.close, cr, ctx.col(.title_text));
                ctx.updateControl(close_id, cr, opt);
                if (ctx.mouse_pressed.eql(.{ .left = true }) and close_id == ctx.focus) {
                    cnt.open = false;
                }
            }
        }

        ctx.pushContainerBody(cnt, body, opt);

        // Resize handle.
        if (!opt.no_resize) {
            const sz = ctx.style.title_height;
            const resize_id = ctx.getId("!resize");
            const rr = rect(r.x + r.w - sz, r.y + r.h - sz, sz, sz);
            ctx.updateControl(resize_id, rr, opt);
            if (resize_id == ctx.focus and ctx.mouse_down.eql(.{ .left = true })) {
                cnt.rect.w = @max(96, cnt.rect.w + ctx.mouse_delta.x);
                cnt.rect.h = @max(64, cnt.rect.h + ctx.mouse_delta.y);
            }
        }

        // Resize to content size.
        if (opt.auto_size) {
            const rr = ctx.getLayout().body;
            cnt.rect.w = cnt.content_size.x + (cnt.rect.w - rr.w);
            cnt.rect.h = cnt.content_size.y + (cnt.rect.h - rr.h);
        }

        // Close popup window if elsewhere was clicked.
        if (opt.popup and !ctx.mouse_pressed.isEmpty() and ctx.hover_root != cnt) {
            cnt.open = false;
        }

        ctx.pushClipRect(cnt.body);
        return .{ .active = true };
    }

    pub fn endWindow(ctx: *Context) void {
        ctx.popClipRect();
        ctx.endRootContainer();
    }

    pub fn openPopup(ctx: *Context, name: []const u8) void {
        const cnt = ctx.getContainer(name);
        // Set as hover root so the popup isn't closed in beginWindowEx.
        ctx.hover_root = cnt;
        ctx.next_hover_root = cnt;
        // Position at the mouse cursor, open and bring to front.
        cnt.rect = rect(ctx.mouse_pos.x, ctx.mouse_pos.y, 1, 1);
        cnt.open = true;
        ctx.bringToFront(cnt);
    }

    pub fn beginPopup(ctx: *Context, name: []const u8) Result {
        return ctx.beginWindowEx(name, rect(0, 0, 0, 0), .{
            .popup = true,
            .auto_size = true,
            .no_resize = true,
            .no_scroll = true,
            .no_title = true,
            .closed = true,
        });
    }

    pub fn endPopup(ctx: *Context) void {
        ctx.endWindow();
    }

    pub fn beginPanel(ctx: *Context, name: []const u8) void {
        ctx.beginPanelEx(name, .{});
    }

    pub fn beginPanelEx(ctx: *Context, name: []const u8, opt: Options) void {
        ctx.pushId(name);
        const cnt = ctx.getContainerImpl(ctx.last_id, opt).?;
        cnt.rect = ctx.layoutNext();
        if (!opt.no_frame) {
            ctx.draw_frame(ctx, cnt.rect, .panel_bg);
        }
        ctx.container_stack.push(cnt);
        ctx.pushContainerBody(cnt, cnt.rect, opt);
        ctx.pushClipRect(cnt.body);
    }

    pub fn endPanel(ctx: *Context) void {
        ctx.popClipRect();
        ctx.popContainer();
    }

    // ------------------------------------------------------------------
    // Pools
    // ------------------------------------------------------------------

    fn inputTextStr(ctx: *Context) []const u8 {
        return cstr(&ctx.input_text);
    }
};

// ===========================================================================
// Free helpers
// ===========================================================================

fn hash(h: *Id, data: []const u8) void {
    for (data) |b| {
        h.* = (h.* ^ b) *% 16777619;
    }
}

fn expandRect(r: Rect, n: i32) Rect {
    return rect(r.x - n, r.y - n, r.w + n * 2, r.h + n * 2);
}

fn intersectRects(r1: Rect, r2: Rect) Rect {
    const x1 = @max(r1.x, r2.x);
    const y1 = @max(r1.y, r2.y);
    var x2 = @min(r1.x + r1.w, r2.x + r2.w);
    var y2 = @min(r1.y + r1.h, r2.y + r2.h);
    if (x2 < x1) x2 = x1;
    if (y2 < y1) y2 = y1;
    return rect(x1, y1, x2 - x1, y2 - y1);
}

fn rectOverlapsVec2(r: Rect, p: Vec2) bool {
    return p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h;
}

fn defaultDrawFrame(ctx: *Context, r: Rect, colorid: ColorId) void {
    ctx.drawRect(r, ctx.col(colorid));
    if (colorid == .scroll_base or colorid == .scroll_thumb or colorid == .title_bg) return;
    // Draw border.
    if (ctx.col(.border).a != 0) {
        ctx.drawBox(expandRect(r, 1), ctx.col(.border));
    }
}

fn poolInit(ctx: *Context, items: []PoolItem, id: Id) usize {
    var n: ?usize = null;
    var f = ctx.frame;
    for (items, 0..) |item, i| {
        if (item.last_update < f) {
            f = item.last_update;
            n = i;
        }
    }
    const idx = n.?;
    items[idx].id = id;
    poolUpdate(ctx, items, idx);
    return idx;
}

fn poolGet(items: []const PoolItem, id: Id) ?usize {
    for (items, 0..) |item, i| {
        if (item.id == id) return i;
    }
    return null;
}

fn poolUpdate(ctx: *Context, items: []PoolItem, idx: usize) void {
    items[idx].last_update = ctx.frame;
}

/// Character at `i` in a slice, treating out-of-range as a null terminator.
inline fn charAt(s: []const u8, i: usize) u8 {
    return if (i < s.len) s[i] else 0;
}

/// Length of a null-terminated string within a buffer.
fn cstrLen(buf: []const u8) usize {
    return std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
}

/// Slice of a buffer up to its null terminator.
fn cstr(buf: []const u8) []const u8 {
    return buf[0..cstrLen(buf)];
}

fn fmtReal(buf: []u8, value: Real, decimals: usize) []const u8 {
    return std.fmt.float.render(buf, value, .{ .mode = .decimal, .precision = decimals }) catch buf[0..0];
}

inline fn toF(x: i32) Real {
    return @floatFromInt(x);
}

inline fn toI(x: Real) i32 {
    return @intFromFloat(x);
}

test {
    _ = @import("zicroui_test.zig");
}
