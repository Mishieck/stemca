const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const format = b.createModule(.{
        .root_source_file = b.path("src/format.zig"),
        .target = target,
    });

    const test_utils = b.createModule(.{
        .root_source_file = b.path("src/test_utils.zig"),
        .target = target,
    });

    const mod = b.addModule("stemca", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "format", .module = format },
            .{ .name = "test_utils", .module = test_utils },
        },
    });

    const row_iterator = b.createModule(.{
        .root_source_file = b.path("src/Database/Table/RowIterator.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "format", .module = format },
            .{ .name = "test_utils", .module = test_utils },
        },
    });

    const table = b.createModule(.{
        .root_source_file = b.path("src/Database/Table.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "format", .module = format },
            .{ .name = "test_utils", .module = test_utils },
        },
    });

    const database = b.createModule(.{
        .root_source_file = b.path("src/Database.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "format", .module = format },
            .{ .name = "test_utils", .module = test_utils },
        },
    });

    const row = b.createModule(.{
        .root_source_file = b.path("src/Database/Table/Row.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "format", .module = format },
            .{ .name = "test_utils", .module = test_utils },
        },
    });

    const exe = b.addExecutable(.{
        .name = "stemca",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "stemca", .module = mod },
                .{ .name = "format", .module = format },
                .{ .name = "test_utils", .module = test_utils },
            },
        }),
    });

    moveAssets(b, exe);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    addModuleTest(b, "test-format", "Run format tests", format);
    addModuleTest(b, "test-row-iterator", "Run RowIterator tests", row_iterator);
    addModuleTest(b, "test-table", "Run Table tests", table);
    addModuleTest(b, "test-database", "Run Database tests", database);
    addModuleTest(b, "test-row", "Run Row tests", row);
    addModuleTest(b, "test-test-utils", "Run test_utils tests", test_utils);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

fn addModuleTest(
    b: *std.Build,
    title: []const u8,
    description: []const u8,
    mod: *std.Build.Module,
) void {
    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step(title, description);
    test_step.dependOn(&run_tests.step);
}

fn moveAssets(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const assets_dir = "database";

    const install_assets = b.addInstallDirectory(.{
        .source_dir = b.path(assets_dir),
        .install_dir = .bin,
        .install_subdir = assets_dir,
    });

    install_assets.step.dependOn(&exe.step);
    b.getInstallStep().dependOn(&install_assets.step);
}
