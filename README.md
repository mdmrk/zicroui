# zicroui

A tiny, portable, immediate-mode UI library for Zig. An idiomatic port of
rxi's [microui](https://github.com/rxi/microui).

zicroui performs no allocation: all state lives in a single `Context`. It is
renderer-agnostic. Each frame it produces a list of drawing commands; the host
feeds input and renders the commands. An optional wio + OpenGL backend is
included.

## Install

Fetch the package:

```sh
zig fetch --save git+https://github.com/mdmrk/zicroui
```

Add the module in `build.zig`:

```zig
const zicroui = b.dependency("zicroui", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zicroui", zicroui.module("zicroui"));
```

To also build the optional wio + OpenGL backend, set the `backend` option to
`.wio` (this pulls in the wio dependency):

```zig
const zicroui = b.dependency("zicroui", .{
    .target = target,
    .optimize = optimize,
    .backend = .wio,
});
```

## Usage

The core only needs two text-metric callbacks from the host; everything else
is input and command rendering.

```zig
const zu = @import("zicroui");

var ctx: zu.Context = undefined;
ctx.init();
ctx.text_width = myTextWidth;   // fn (zu.Font, []const u8) i32
ctx.text_height = myTextHeight; // fn (zu.Font) i32

// Per frame:
//   feed input
ctx.inputMouseMove(x, y);
ctx.inputMouseDown(x, y, .{ .left = true });
// ... inputMouseUp, inputScroll, inputKeyDown/Up, inputText

//   build the UI
ctx.begin();
if (ctx.beginWindow("Hello", zu.rect(40, 40, 300, 200)).active) {
    if (ctx.button("Click me").submit) {
        // handle click
    }
    ctx.endWindow();
}
ctx.end();

//   render the command list
var it = ctx.commandIterator();
while (it.next()) |cmd| switch (cmd) {
    .rect => |r| myDrawRect(r.rect, r.color),
    .text => |t| myDrawText(t.str, t.pos, t.color),
    .icon => |ic| myDrawIcon(ic.id, ic.rect, ic.color),
    .clip => |r| mySetClip(r),
    .jump => {}, // the iterator follows jumps automatically
};
```

## Optional wio + OpenGL backend

When built with `-Dbackend=wio`, the backend is exposed as
`zicroui.backend`. It provides the text-metric callbacks, input translation,
and a fixed-function OpenGL renderer with a bundled font/icon atlas, so a host
only writes its UI code.

```zig
const zu = @import("zicroui");
const backend = zu.backend;

try backend.init(width, height);

var ctx: zu.Context = undefined;
ctx.init();
backend.attach(&ctx); // wires up the text-metric callbacks

// Per frame:
while (events.pop()) |event| {
    if (event == .close) break;
    backend.processEvent(&ctx, event);
}

ctx.begin();
// ... build UI ...
ctx.end();

backend.clear(bg_color);
backend.render(&ctx);
backend.present(&window);
```

Without the option the backend is an empty namespace and the wio dependency is
never fetched.

## Building

```sh
zig build              # build the static library
zig build test         # run unit tests
zig build demo         # build the demo (backend defaults to wio here)
zig build run          # build and run the demo
zig build docs         # generate documentation
```
