const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The wio + OpenGL backend pulls in the wio dependency, so it is opt-in.
    // It defaults on when building zicroui directly (so `zig build run` works)
    // and off when zicroui is consumed as a dependency, unless the consumer
    // passes `.@"wio-backend" = true`.
    const is_root = b.pkg_hash.len == 0;
    const enable_wio_backend = b.option(
        bool,
        "wio-backend",
        "Build the optional wio + OpenGL backend module",
    ) orelse is_root;

    const mod = b.addModule("zicroui", .{
        .root_source_file = b.path("src/zicroui.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Compile-time switch read by src/zicroui.zig to decide whether to expose
    // the `backend` namespace.
    const options = b.addOptions();
    options.addOption(bool, "wio_backend", enable_wio_backend);
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

    if (!enable_wio_backend) return;

    // `wio` is a lazy dependency: it is only fetched when the backend (and
    // therefore the demo) is actually built. The backend lives inside the
    // zicroui module (exposed as `zicroui.backend`), so the wio import is
    // added to the module itself rather than to a separate package.
    const wio = b.lazyDependency("wio", .{
        .target = target,
        .optimize = optimize,
        .enable_opengl = true,
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
