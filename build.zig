const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        //.shared = true,
    });

    const raylib = raylib_dep.module("raylib"); 
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib"); 
   
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/exsw.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("EXSW", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "EXSW",
        .root_module = lib_mod,
    });
    
    lib.linkLibrary(raylib_artifact);
    lib.root_module.addImport("raylib", raylib);
    lib.root_module.addImport("raygui", raygui);

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
