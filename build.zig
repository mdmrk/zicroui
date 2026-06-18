const std = @import("std");

/// Selectable rendering/input backend. A backend other than `.none` pulls in
/// its own dependencies (e.g. `.wio` pulls in wio), so it is opt-in.
const Backend = enum { none, wio };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The backend defaults to `.wio` when building zicroui directly (so
    // `zig build run` works) and to `.none` when zicroui is consumed as a
    // dependency, unless the consumer passes `.backend = .wio`.
    const is_root = b.pkg_hash.len == 0;
    const backend = b.option(
        Backend,
        "backend",
        "Rendering/input backend to build (none, wio)",
    ) orelse if (is_root) Backend.wio else .none;

    const mod = b.addModule("zicroui", .{
        .root_source_file = b.path("src/zicroui.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Compile-time switch read by src/zicroui.zig to decide which `backend`
    // namespace to expose.
    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);
    mod.addOptions("build_options", options);

    const lib = b.addLibrary(.{
        .name = "zicroui",
        .root_module = mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build and install documentation");
    docs_step.dependOn(&install_docs.step);

    if (backend != .wio) return;

    // `wio` is a lazy dependency: it is only fetched when the wio backend (and
    // therefore the demo) is actually built. The backend lives inside the
    // zicroui module (exposed as `zicroui.backend`), so the wio import is
    // added to the module itself rather than to a separate package.
    const wio = b.lazyDependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_opengl = true,
        .enable_drop = true,
    }) orelse return;
    const wio_mod = wio.module("wio");
    mod.addImport("wio", wio_mod);

    const demo_mod = b.createModule(.{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("zicroui", mod);
    demo_mod.addImport("wio", wio_mod);

    const demo = b.addExecutable(.{
        .name = "zicroui-demo",
        .root_module = demo_mod,
    });

    const demo_step = b.step("demo", "Build the demo");
    demo_step.dependOn(&b.addInstallArtifact(demo, .{}).step);

    const run_demo = b.addRunArtifact(demo);
    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&run_demo.step);
}
