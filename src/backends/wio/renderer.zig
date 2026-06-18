//! Faithful port of the microui demo renderer (originally renderer.c).
//! Batches textured quads from a font/icon atlas and draws them with
//! fixed-function OpenGL through wio's GL context.

const wio = @import("wio");
const zu = @import("../../zicroui.zig");
const gl = @import("gl.zig");
const atlas = @import("atlas.zig");

const buffer_size = 16384;

var tex_buf: [buffer_size * 8]gl.Float = undefined;
var vert_buf: [buffer_size * 8]gl.Float = undefined;
var color_buf: [buffer_size * 16]gl.Ubyte = undefined;
var index_buf: [buffer_size * 6]gl.Uint = undefined;
var buf_idx: usize = 0;

var width: i32 = 800;
var height: i32 = 600;

pub fn init(w: i32, h: i32) !void {
    width = w;
    height = h;

    try gl.load();

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.disable(gl.CULL_FACE);
    gl.disable(gl.DEPTH_TEST);
    gl.enable(gl.SCISSOR_TEST);
    gl.enable(gl.TEXTURE_2D);
    gl.enableClientState(gl.VERTEX_ARRAY);
    gl.enableClientState(gl.TEXTURE_COORD_ARRAY);
    gl.enableClientState(gl.COLOR_ARRAY);

    // Upload the alpha atlas texture.
    var id: gl.Uint = undefined;
    gl.genTextures(1, @ptrCast(&id));
    gl.bindTexture(gl.TEXTURE_2D, id);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.ALPHA, atlas.width, atlas.height, 0, gl.ALPHA, gl.UNSIGNED_BYTE, @ptrCast(&atlas.texture));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
}

pub fn setSize(w: i32, h: i32) void {
    width = w;
    height = h;
}

fn flush() void {
    if (buf_idx == 0) return;

    gl.viewport(0, 0, width, height);
    gl.matrixMode(gl.PROJECTION);
    gl.pushMatrix();
    gl.loadIdentity();
    gl.ortho(0, @floatFromInt(width), @floatFromInt(height), 0, -1, 1);
    gl.matrixMode(gl.MODELVIEW);
    gl.pushMatrix();
    gl.loadIdentity();

    gl.texCoordPointer(2, gl.FLOAT, 0, @ptrCast(&tex_buf));
    gl.vertexPointer(2, gl.FLOAT, 0, @ptrCast(&vert_buf));
    gl.colorPointer(4, gl.UNSIGNED_BYTE, 0, @ptrCast(&color_buf));
    gl.drawElements(gl.TRIANGLES, @intCast(buf_idx * 6), gl.UNSIGNED_INT, @ptrCast(&index_buf));

    gl.matrixMode(gl.MODELVIEW);
    gl.popMatrix();
    gl.matrixMode(gl.PROJECTION);
    gl.popMatrix();

    buf_idx = 0;
}

fn pushQuad(dst: zu.Rect, src: zu.Rect, color: zu.Color) void {
    if (buf_idx == buffer_size) flush();

    const texvert_idx = buf_idx * 8;
    const color_idx = buf_idx * 16;
    const element_idx: gl.Uint = @intCast(buf_idx * 4);
    const index_idx = buf_idx * 6;
    buf_idx += 1;

    // Texture coordinates (normalised into the atlas).
    const x: gl.Float = @as(gl.Float, @floatFromInt(src.x)) / atlas.width;
    const y: gl.Float = @as(gl.Float, @floatFromInt(src.y)) / atlas.height;
    const w: gl.Float = @as(gl.Float, @floatFromInt(src.w)) / atlas.width;
    const h: gl.Float = @as(gl.Float, @floatFromInt(src.h)) / atlas.height;
    tex_buf[texvert_idx + 0] = x;
    tex_buf[texvert_idx + 1] = y;
    tex_buf[texvert_idx + 2] = x + w;
    tex_buf[texvert_idx + 3] = y;
    tex_buf[texvert_idx + 4] = x;
    tex_buf[texvert_idx + 5] = y + h;
    tex_buf[texvert_idx + 6] = x + w;
    tex_buf[texvert_idx + 7] = y + h;

    // Vertex positions.
    const dx: gl.Float = @floatFromInt(dst.x);
    const dy: gl.Float = @floatFromInt(dst.y);
    const dw: gl.Float = @floatFromInt(dst.w);
    const dh: gl.Float = @floatFromInt(dst.h);
    vert_buf[texvert_idx + 0] = dx;
    vert_buf[texvert_idx + 1] = dy;
    vert_buf[texvert_idx + 2] = dx + dw;
    vert_buf[texvert_idx + 3] = dy;
    vert_buf[texvert_idx + 4] = dx;
    vert_buf[texvert_idx + 5] = dy + dh;
    vert_buf[texvert_idx + 6] = dx + dw;
    vert_buf[texvert_idx + 7] = dy + dh;

    // Per-vertex colour (same for all four corners).
    const c = [4]gl.Ubyte{ color.r, color.g, color.b, color.a };
    inline for (0..4) |i| {
        @memcpy(color_buf[color_idx + i * 4 .. color_idx + i * 4 + 4], &c);
    }

    // Two triangles.
    index_buf[index_idx + 0] = element_idx + 0;
    index_buf[index_idx + 1] = element_idx + 1;
    index_buf[index_idx + 2] = element_idx + 2;
    index_buf[index_idx + 3] = element_idx + 2;
    index_buf[index_idx + 4] = element_idx + 3;
    index_buf[index_idx + 5] = element_idx + 1;
}

pub fn drawRect(rect: zu.Rect, color: zu.Color) void {
    pushQuad(rect, atlas.atlas[atlas.white], color);
}

pub fn drawText(text: []const u8, pos: zu.Vec2, color: zu.Color) void {
    var dst = zu.Rect{ .x = pos.x, .y = pos.y, .w = 0, .h = 0 };
    for (text) |ch| {
        if ((ch & 0xc0) == 0x80) continue; // skip utf-8 continuation bytes
        const chr = @min(ch, 127);
        const src = atlas.atlas[atlas.font + @as(usize, chr)];
        dst.w = src.w;
        dst.h = src.h;
        pushQuad(dst, src, color);
        dst.x += dst.w;
    }
}

pub fn drawIcon(id: usize, rect: zu.Rect, color: zu.Color) void {
    const src = atlas.atlas[id];
    const x = rect.x + @divTrunc(rect.w - src.w, 2);
    const y = rect.y + @divTrunc(rect.h - src.h, 2);
    pushQuad(zu.rect(x, y, src.w, src.h), src, color);
}

pub fn getTextWidth(text: []const u8) i32 {
    var res: i32 = 0;
    for (text) |ch| {
        if ((ch & 0xc0) == 0x80) continue;
        const chr = @min(ch, 127);
        res += atlas.atlas[atlas.font + @as(usize, chr)].w;
    }
    return res;
}

pub fn getTextHeight() i32 {
    return 18;
}

// Callbacks matching the zicroui text-metric signatures.
pub fn textWidth(font: zu.Font, str: []const u8) i32 {
    _ = font;
    return getTextWidth(str);
}

pub fn textHeight(font: zu.Font) i32 {
    _ = font;
    return getTextHeight();
}

pub fn setClip(rect: zu.Rect) void {
    flush();
    gl.scissor(rect.x, height - (rect.y + rect.h), rect.w, rect.h);
}

pub fn clear(color: zu.Color) void {
    flush();
    gl.scissor(0, 0, width, height);
    gl.clearColor(
        @as(gl.Float, @floatFromInt(color.r)) / 255.0,
        @as(gl.Float, @floatFromInt(color.g)) / 255.0,
        @as(gl.Float, @floatFromInt(color.b)) / 255.0,
        @as(gl.Float, @floatFromInt(color.a)) / 255.0,
    );
    gl.clear(gl.COLOR_BUFFER_BIT);
}

pub fn present(window: *wio.Window) void {
    flush();
    window.glSwapBuffers();
}
