const std = @import("std");
const zu = @import("zicroui.zig");

// A trivial monospace-like text metric so controls have non-zero geometry.
fn textWidth(font: zu.Font, str: []const u8) i32 {
    _ = font;
    return @intCast(str.len * 8);
}

fn textHeight(font: zu.Font) i32 {
    _ = font;
    return 16;
}

fn makeContext(ctx: *zu.Context) void {
    ctx.init();
    ctx.text_width = textWidth;
    ctx.text_height = textHeight;
}

test "init sets defaults" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);
    try std.testing.expectEqual(zu.color(230, 230, 230, 255), ctx.style.colors[@intFromEnum(zu.ColorId.text)]);
    try std.testing.expectEqual(@as(zu.Id, 0), ctx.focus);
}

test "empty frame produces no drawable commands" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);
    ctx.begin();
    ctx.end();
    var it = ctx.commandIterator();
    try std.testing.expect(it.next() == null);
}

test "window with controls emits commands" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);

    var checked = false;
    var slider_val: zu.Real = 5;

    ctx.begin();
    if (ctx.beginWindow("Test", zu.rect(10, 10, 200, 200)).active) {
        ctx.layoutRow(&[_]i32{ 90, -1 }, 0);
        ctx.label("Hello:");
        _ = ctx.button("Click");
        _ = ctx.checkbox("Check", &checked);
        _ = ctx.slider(&slider_val, 0, 10);
        ctx.text("Some wrapped text that spans multiple words and lines.");
        ctx.endWindow();
    }
    ctx.end();

    var saw_rect = false;
    var saw_text = false;
    var it = ctx.commandIterator();
    while (it.next()) |cmd| {
        switch (cmd) {
            .rect => saw_rect = true,
            .text => saw_text = true,
            else => {},
        }
    }
    try std.testing.expect(saw_rect);
    try std.testing.expect(saw_text);
}

// Runs a single frame containing one button in a window, returning whether the
// button reported a submit.
fn buttonFrame(ctx: *zu.Context) bool {
    ctx.begin();
    defer ctx.end();
    var clicked = false;
    _ = ctx.beginWindow("W", zu.rect(0, 0, 200, 200));
    ctx.layoutRow(&[_]i32{-1}, 0);
    if (ctx.button("Go").submit) clicked = true;
    ctx.endWindow();
    return clicked;
}

test "button click is reported on left press inside" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);

    // Hover persists across frames, so it takes a couple of frames over the
    // control before a press resolves to a click:
    //   frame 1 establishes the hover root, frame 2 sets `hover`,
    //   frame 3 (with the press) resolves to a submit.
    ctx.inputMouseMove(40, 38);
    try std.testing.expect(!buttonFrame(&ctx)); // establish hover root
    try std.testing.expect(!buttonFrame(&ctx)); // establish hover

    ctx.inputMouseDown(40, 38, .{ .left = true });
    try std.testing.expect(buttonFrame(&ctx)); // press -> submit
}

fn checkboxFrame(ctx: *zu.Context, state: *bool) void {
    ctx.begin();
    defer ctx.end();
    _ = ctx.beginWindow("W", zu.rect(0, 0, 200, 200));
    ctx.layoutRow(&[_]i32{-1}, 0);
    _ = ctx.checkbox("C", state);
    ctx.endWindow();
}

test "checkbox toggles on click" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);
    var checked = false;

    ctx.inputMouseMove(20, 30);
    checkboxFrame(&ctx, &checked); // establish hover root
    checkboxFrame(&ctx, &checked); // establish hover
    try std.testing.expect(!checked);

    ctx.inputMouseDown(20, 30, .{ .left = true });
    checkboxFrame(&ctx, &checked); // press -> toggle
    try std.testing.expect(checked);
}

test "id hashing is stable and path-sensitive" {
    var ctx: zu.Context = undefined;
    makeContext(&ctx);
    const a = ctx.getId("foo");
    const b = ctx.getId("foo");
    const c = ctx.getId("bar");
    try std.testing.expectEqual(a, b);
    try std.testing.expect(a != c);

    ctx.pushId("scope");
    const scoped = ctx.getId("foo");
    ctx.popId();
    try std.testing.expect(scoped != a);
}

test "flag sets behave like bitmasks" {
    const left: zu.MouseButtons = .{ .left = true };
    const right: zu.MouseButtons = .{ .right = true };
    const both = left.merge(right);
    try std.testing.expect(both.contains(left));
    try std.testing.expect(both.contains(right));
    try std.testing.expect(!both.eql(left));
    try std.testing.expect(both.remove(right).eql(left));
    try std.testing.expect((zu.MouseButtons{}).isEmpty());
}
