//! Minimal loader for the fixed-function OpenGL 1.x entry points used by the
//! zicroui demo renderer. Function pointers are resolved through wio's
//! `glGetProcAddress` once a compatibility context is current.

const wio = @import("wio");

pub const Enum = u32;
pub const Bitfield = u32;
pub const Int = i32;
pub const Sizei = i32;
pub const Uint = u32;
pub const Float = f32;
pub const Double = f64;
pub const Ubyte = u8;

// Constants (from the OpenGL 1.1 headers).
pub const TRIANGLES: Enum = 0x0004;
pub const SRC_ALPHA: Enum = 0x0302;
pub const ONE_MINUS_SRC_ALPHA: Enum = 0x0303;
pub const CULL_FACE: Enum = 0x0B44;
pub const DEPTH_TEST: Enum = 0x0B71;
pub const BLEND: Enum = 0x0BE2;
pub const SCISSOR_TEST: Enum = 0x0C11;
pub const TEXTURE_2D: Enum = 0x0DE1;
pub const UNSIGNED_BYTE: Enum = 0x1401;
pub const UNSIGNED_INT: Enum = 0x1405;
pub const FLOAT: Enum = 0x1406;
pub const ALPHA: Enum = 0x1906;
pub const MODELVIEW: Enum = 0x1700;
pub const PROJECTION: Enum = 0x1701;
pub const NEAREST: Enum = 0x2600;
pub const TEXTURE_MAG_FILTER: Enum = 0x2800;
pub const TEXTURE_MIN_FILTER: Enum = 0x2801;
pub const VERTEX_ARRAY: Enum = 0x8074;
pub const COLOR_ARRAY: Enum = 0x8076;
pub const TEXTURE_COORD_ARRAY: Enum = 0x8078;
pub const COLOR_BUFFER_BIT: Bitfield = 0x4000;

pub var enable: *const fn (Enum) callconv(.c) void = undefined;
pub var disable: *const fn (Enum) callconv(.c) void = undefined;
pub var blendFunc: *const fn (Enum, Enum) callconv(.c) void = undefined;
pub var enableClientState: *const fn (Enum) callconv(.c) void = undefined;
pub var genTextures: *const fn (Sizei, [*]Uint) callconv(.c) void = undefined;
pub var bindTexture: *const fn (Enum, Uint) callconv(.c) void = undefined;
pub var texImage2D: *const fn (Enum, Int, Int, Sizei, Sizei, Int, Enum, Enum, ?*const anyopaque) callconv(.c) void = undefined;
pub var texParameteri: *const fn (Enum, Enum, Int) callconv(.c) void = undefined;
pub var viewport: *const fn (Int, Int, Sizei, Sizei) callconv(.c) void = undefined;
pub var matrixMode: *const fn (Enum) callconv(.c) void = undefined;
pub var pushMatrix: *const fn () callconv(.c) void = undefined;
pub var popMatrix: *const fn () callconv(.c) void = undefined;
pub var loadIdentity: *const fn () callconv(.c) void = undefined;
pub var ortho: *const fn (Double, Double, Double, Double, Double, Double) callconv(.c) void = undefined;
pub var texCoordPointer: *const fn (Int, Enum, Sizei, ?*const anyopaque) callconv(.c) void = undefined;
pub var vertexPointer: *const fn (Int, Enum, Sizei, ?*const anyopaque) callconv(.c) void = undefined;
pub var colorPointer: *const fn (Int, Enum, Sizei, ?*const anyopaque) callconv(.c) void = undefined;
pub var drawElements: *const fn (Enum, Sizei, Enum, ?*const anyopaque) callconv(.c) void = undefined;
pub var scissor: *const fn (Int, Int, Sizei, Sizei) callconv(.c) void = undefined;
pub var clearColor: *const fn (Float, Float, Float, Float) callconv(.c) void = undefined;
pub var clear: *const fn (Bitfield) callconv(.c) void = undefined;

/// Resolve all entry points. Must be called with a current GL context.
pub fn load() error{MissingSymbol}!void {
    try bind(&enable, "glEnable");
    try bind(&disable, "glDisable");
    try bind(&blendFunc, "glBlendFunc");
    try bind(&enableClientState, "glEnableClientState");
    try bind(&genTextures, "glGenTextures");
    try bind(&bindTexture, "glBindTexture");
    try bind(&texImage2D, "glTexImage2D");
    try bind(&texParameteri, "glTexParameteri");
    try bind(&viewport, "glViewport");
    try bind(&matrixMode, "glMatrixMode");
    try bind(&pushMatrix, "glPushMatrix");
    try bind(&popMatrix, "glPopMatrix");
    try bind(&loadIdentity, "glLoadIdentity");
    try bind(&ortho, "glOrtho");
    try bind(&texCoordPointer, "glTexCoordPointer");
    try bind(&vertexPointer, "glVertexPointer");
    try bind(&colorPointer, "glColorPointer");
    try bind(&drawElements, "glDrawElements");
    try bind(&scissor, "glScissor");
    try bind(&clearColor, "glClearColor");
    try bind(&clear, "glClear");
}

fn bind(ptr: anytype, comptime name: [:0]const u8) error{MissingSymbol}!void {
    const proc = wio.glGetProcAddress(name) orelse return error.MissingSymbol;
    ptr.* = @ptrCast(proc);
}
