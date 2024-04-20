const std = @import("std");
const builtin = @import("builtin");

comptime {
    const required_zig = "0.12.0-dev.2150+63de8a598";
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(required_zig) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Your Zig version v{} does not meet the minimum build requirement of v{}",
            .{ current_zig, min_zig },
        ));
    }
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Module declarations
    const strings = b.addModule("sonic-strings", .{ .root_source_file = .{ .path = "src/strings.zig" } });
    const sonic = b.addModule("sonic", .{ .root_source_file = .{ .path = "src/records.zig" } });
    sonic.addImport("strings", strings);

    const fastaModule = b.addModule("sonic-fasta", .{ .root_source_file = .{ .path = "src/fasta-lib.zig" } });
    fastaModule.addImport("strings", strings);
    fastaModule.addImport("sonic", sonic);

    const fasta = b.addExecutable(.{
        .name = "pdb2fasta",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/fasta.zig" },
        .target = target,
        .optimize = optimize,
        .use_lld = false,
        .use_llvm = false,
    });
    fasta.root_module.addImport("sonic-fasta", fastaModule);
    fasta.root_module.addImport("sonic", sonic);
    fasta.root_module.addImport("strings", strings);
    // fasta.root_module.addImport("strings", strings);
    // fasta.root_module.addImport("records", sonic);
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(fasta);

    const exe = b.addExecutable(.{
        .name = "sonic-pdb-parser",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .use_lld = false,
        .use_llvm = false,
    });
    exe.root_module.addImport("sonic", sonic);
    exe.root_module.addImport("strings", strings);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });
    unit_tests.root_module.addImport("sonic", sonic);
    unit_tests.root_module.addImport("strings", strings);

    const sonic_test = b.addTest(.{
        .root_source_file = b.path("src/records.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });
    sonic_test.root_module.addImport("strings", strings);

    const strings_test = b.addTest(.{
        .root_source_file = b.path("src/strings.zig"),
        .target = target,
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_sonic_tests = b.addRunArtifact(sonic_test);
    const run_strings_tests = b.addRunArtifact(strings_test);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_sonic_tests.step);
    test_step.dependOn(&run_strings_tests.step);

    // const install_docs = b.addInstallDirectory(.{
    //     .source_dir = lib.getEmittedDocs(),
    //     .install_dir = .prefix,
    //     .install_subdir = "doc",
    // });

    // const docs_step = b.step("docs", "Generate docs");
    // docs_step.dependOn(&install_docs.step);
    // docs_step.dependOn(&lib.step);
}
