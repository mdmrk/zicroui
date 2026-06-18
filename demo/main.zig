//! zicroui demo, ported from demo/main.c, using wio for the window/input/GL
//! backend and the idiomatic zicroui API.

const std = @import("std");
const wio = @import("wio");
const zu = @import("zicroui");
const renderer = @import("renderer.zig");

comptime {
    _ = wio; // ensure the entry point is exported on platforms that need it
}

pub const std_options: std.Options = .{
    .logFn = wio.logFn,
};

// Last known mouse position; wio button events do not carry a position.
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;

// Stable storage for uint8Slider's scratch value (its address seeds a control
// id, so it must not change between frames).
var uint8_tmp: zu.Real = 0;

const Ui = struct {
    logbuf: [64000]u8 = undefined,
    logbuf_len: usize = 0,
    logbuf_updated: bool = false,
    bg: [3]zu.Real = .{ 90, 95, 100 },
    checks: [3]bool = .{ true, false, true },
    textbox_buf: [128]u8 = undefined,

    fn init(self: *Ui) void {
        self.logbuf[0] = 0;
        self.textbox_buf[0] = 0;
    }

    fn writeLog(self: *Ui, text: []const u8) void {
        if (self.logbuf_len != 0 and self.logbuf_len < self.logbuf.len) {
            self.logbuf[self.logbuf_len] = '\n';
            self.logbuf_len += 1;
        }
        const n = @min(text.len, self.logbuf.len - self.logbuf_len);
        @memcpy(self.logbuf[self.logbuf_len .. self.logbuf_len + n], text[0..n]);
        self.logbuf_len += n;
        self.logbuf_updated = true;
    }
};

fn cstr(buf: []const u8) []const u8 {
    const n = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
    return buf[0..n];
}

// ===========================================================================
// Demo windows
// ===========================================================================

fn testWindow(ctx: *zu.Context, ui: *Ui) void {
    if (!ctx.beginWindow("Demo Window", zu.rect(40, 40, 300, 450)).active) return;
    defer ctx.endWindow();

    const win = ctx.getCurrentContainer();
    win.rect.w = @max(win.rect.w, 240);
    win.rect.h = @max(win.rect.h, 300);

    // Window info.
    if (ctx.header("Window Info").active) {
        var buf: [64]u8 = undefined;
        ctx.layoutRow(&[_]i32{ 54, -1 }, 0);
        ctx.label("Position:");
        ctx.label(std.fmt.bufPrint(&buf, "{d}, {d}", .{ win.rect.x, win.rect.y }) catch "");
        ctx.label("Size:");
        ctx.label(std.fmt.bufPrint(&buf, "{d}, {d}", .{ win.rect.w, win.rect.h }) catch "");
    }

    // Labels + buttons.
    if (ctx.headerEx("Test Buttons", .{ .expanded = true }).active) {
        ctx.layoutRow(&[_]i32{ 86, -110, -1 }, 0);
        ctx.label("Test buttons 1:");
        if (ctx.button("Button 1").submit) ui.writeLog("Pressed button 1");
        if (ctx.button("Button 2").submit) ui.writeLog("Pressed button 2");
        ctx.label("Test buttons 2:");
        if (ctx.button("Button 3").submit) ui.writeLog("Pressed button 3");
        if (ctx.button("Popup").submit) ctx.openPopup("Test Popup");
        if (ctx.beginPopup("Test Popup").active) {
            _ = ctx.button("Hello");
            _ = ctx.button("World");
            ctx.endPopup();
        }
    }

    // Tree and text.
    if (ctx.headerEx("Tree and Text", .{ .expanded = true }).active) {
        ctx.layoutRow(&[_]i32{ 140, -1 }, 0);
        ctx.layoutBeginColumn();
        if (ctx.beginTreenode("Test 1").active) {
            if (ctx.beginTreenode("Test 1a").active) {
                ctx.label("Hello");
                ctx.label("world");
                ctx.endTreenode();
            }
            if (ctx.beginTreenode("Test 1b").active) {
                if (ctx.button("Button 1").submit) ui.writeLog("Pressed button 1");
                if (ctx.button("Button 2").submit) ui.writeLog("Pressed button 2");
                ctx.endTreenode();
            }
            ctx.endTreenode();
        }
        if (ctx.beginTreenode("Test 2").active) {
            ctx.layoutRow(&[_]i32{ 54, 54 }, 0);
            if (ctx.button("Button 3").submit) ui.writeLog("Pressed button 3");
            if (ctx.button("Button 4").submit) ui.writeLog("Pressed button 4");
            if (ctx.button("Button 5").submit) ui.writeLog("Pressed button 5");
            if (ctx.button("Button 6").submit) ui.writeLog("Pressed button 6");
            ctx.endTreenode();
        }
        if (ctx.beginTreenode("Test 3").active) {
            ctx.layoutRow(&[_]i32{-1}, 0);
            _ = ctx.checkbox("Checkbox 1", &ui.checks[0]);
            _ = ctx.checkbox("Checkbox 2", &ui.checks[1]);
            _ = ctx.checkbox("Checkbox 3", &ui.checks[2]);
            ctx.endTreenode();
        }
        ctx.layoutEndColumn();

        ctx.layoutBeginColumn();
        ctx.layoutRow(&[_]i32{-1}, 0);
        ctx.text("Lorem ipsum dolor sit amet, consectetur adipiscing " ++
            "elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " ++
            "ipsum, eu varius magna felis a nulla.");
        ctx.layoutEndColumn();
    }

    // Background color sliders.
    if (ctx.headerEx("Background Color", .{ .expanded = true }).active) {
        ctx.layoutRow(&[_]i32{ -78, -1 }, 74);
        // Sliders.
        ctx.layoutBeginColumn();
        ctx.layoutRow(&[_]i32{ 46, -1 }, 0);
        ctx.label("Red:");
        _ = ctx.slider(&ui.bg[0], 0, 255);
        ctx.label("Green:");
        _ = ctx.slider(&ui.bg[1], 0, 255);
        ctx.label("Blue:");
        _ = ctx.slider(&ui.bg[2], 0, 255);
        ctx.layoutEndColumn();
        // Color preview.
        const r = ctx.layoutNext();
        ctx.drawRect(r, zu.color(
            @intFromFloat(ui.bg[0]),
            @intFromFloat(ui.bg[1]),
            @intFromFloat(ui.bg[2]),
            255,
        ));
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "#{X:0>2}{X:0>2}{X:0>2}", .{
            @as(u8, @intFromFloat(ui.bg[0])),
            @as(u8, @intFromFloat(ui.bg[1])),
            @as(u8, @intFromFloat(ui.bg[2])),
        }) catch "";
        ctx.drawControlText(s, r, .text, .{ .align_center = true });
    }
}

fn logWindow(ctx: *zu.Context, ui: *Ui) void {
    if (!ctx.beginWindow("Log Window", zu.rect(350, 40, 300, 200)).active) return;
    defer ctx.endWindow();

    // Output text panel.
    ctx.layoutRow(&[_]i32{-1}, -25);
    ctx.beginPanel("Log Output");
    const panel = ctx.getCurrentContainer();
    ctx.layoutRow(&[_]i32{-1}, -1);
    ctx.text(ui.logbuf[0..ui.logbuf_len]);
    ctx.endPanel();
    if (ui.logbuf_updated) {
        panel.scroll.y = panel.content_size.y;
        ui.logbuf_updated = false;
    }

    // Input textbox + submit button.
    var submitted = false;
    ctx.layoutRow(&[_]i32{ -70, -1 }, 0);
    if (ctx.textbox(&ui.textbox_buf).submit) {
        ctx.setFocus(ctx.last_id);
        submitted = true;
    }
    if (ctx.button("Submit").submit) submitted = true;
    if (submitted) {
        ui.writeLog(cstr(&ui.textbox_buf));
        ui.textbox_buf[0] = 0;
    }
}

fn uint8Slider(ctx: *zu.Context, value: *u8, low: zu.Real, high: zu.Real) zu.Result {
    uint8_tmp = @floatFromInt(value.*);
    ctx.pushId(std.mem.asBytes(&value));
    const res = ctx.sliderEx(&uint8_tmp, low, high, 0, 0, .{ .align_center = true });
    value.* = @intFromFloat(uint8_tmp);
    ctx.popId();
    return res;
}

const StyleColor = struct { label: []const u8, id: zu.ColorId };
const style_colors = [_]StyleColor{
    .{ .label = "text:", .id = .text },
    .{ .label = "border:", .id = .border },
    .{ .label = "windowbg:", .id = .window_bg },
    .{ .label = "titlebg:", .id = .title_bg },
    .{ .label = "titletext:", .id = .title_text },
    .{ .label = "panelbg:", .id = .panel_bg },
    .{ .label = "button:", .id = .button },
    .{ .label = "buttonhover:", .id = .button_hover },
    .{ .label = "buttonfocus:", .id = .button_focus },
    .{ .label = "base:", .id = .base },
    .{ .label = "basehover:", .id = .base_hover },
    .{ .label = "basefocus:", .id = .base_focus },
    .{ .label = "scrollbase:", .id = .scroll_base },
    .{ .label = "scrollthumb:", .id = .scroll_thumb },
};

fn styleWindow(ctx: *zu.Context) void {
    if (!ctx.beginWindow("Style Editor", zu.rect(350, 250, 300, 240)).active) return;
    defer ctx.endWindow();

    const sw: i32 = @intFromFloat(@as(f32, @floatFromInt(ctx.getCurrentContainer().body.w)) * 0.14);
    for (style_colors) |sc| {
        ctx.layoutRow(&[_]i32{ 80, sw, sw, sw, sw, -1 }, 0);
        ctx.label(sc.label);
        const c = &ctx.style.colors[@intFromEnum(sc.id)];
        _ = uint8Slider(ctx, &c.r, 0, 255);
        _ = uint8Slider(ctx, &c.g, 0, 255);
        _ = uint8Slider(ctx, &c.b, 0, 255);
        _ = uint8Slider(ctx, &c.a, 0, 255);
        ctx.drawRect(ctx.layoutNext(), c.*);
    }
}

fn processFrame(ctx: *zu.Context, ui: *Ui) void {
    ctx.begin();
    styleWindow(ctx);
    logWindow(ctx, ui);
    testWindow(ctx, ui);
    ctx.end();
}

// ===========================================================================
// Input translation
// ===========================================================================

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

// ===========================================================================
// Entry point
// ===========================================================================

var debug_allocator = std.heap.DebugAllocator(.{}).init;
var threaded: std.Io.Threaded = undefined;

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = debug_allocator.allocator();
    threaded = std.Io.Threaded.init(allocator, .{ .environ = init.environ });
    const io = threaded.io();

    try wio.init(allocator, io, wio.EventQueue.eventFn, .{});
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    const gl_options: wio.GlOptions = .{ .api = .gl, .major_version = 1, .minor_version = 0 };

    var window = try wio.Window.create(.{
        .event_fn_data = &events,
        .title = "zicroui (wio)",
        .size = .{ .width = 800, .height = 600 },
        .scale = 1,
        .gl_options = gl_options,
    });
    defer window.destroy();

    const context = try window.glCreateContext(.{ .options = gl_options });
    defer context.destroy();
    window.glMakeContextCurrent(context);
    window.glSwapInterval(1);

    try renderer.init(800, 600);
    window.enableTextInput(.{});

    var ctx: zu.Context = undefined;
    ctx.init();
    ctx.text_width = renderer.textWidth;
    ctx.text_height = renderer.textHeight;

    var ui: Ui = .{};
    ui.init();

    loop: while (true) {
        wio.update();
        while (events.pop()) |event| {
            switch (event) {
                .close => break :loop,
                .size_physical => |s| renderer.setSize(s.width, s.height),
                .mouse => |m| {
                    mouse_x = m.x;
                    mouse_y = m.y;
                    ctx.inputMouseMove(m.x, m.y);
                },
                .button_press => |b| handleButton(&ctx, b, true),
                .button_release => |b| handleButton(&ctx, b, false),
                .char => |c| handleChar(&ctx, c),
                .scroll_vertical => |dy| ctx.inputScroll(0, @intFromFloat(dy * -30)),
                else => {},
            }
        }

        processFrame(&ctx, &ui);

        renderer.clear(zu.color(
            @intFromFloat(ui.bg[0]),
            @intFromFloat(ui.bg[1]),
            @intFromFloat(ui.bg[2]),
            255,
        ));
        var it = ctx.commandIterator();
        while (it.next()) |cmd| switch (cmd) {
            .text => |t| renderer.drawText(t.str, t.pos, t.color),
            .rect => |r| renderer.drawRect(r.rect, r.color),
            .icon => |ic| renderer.drawIcon(@intCast(@intFromEnum(ic.id)), ic.rect, ic.color),
            .clip => |cr| renderer.setClip(cr),
            .jump => {},
        };
        renderer.present(&window);
    }
}
