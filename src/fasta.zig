const std = @import("std");
const records = @import("sonic");
const strings = @import("strings");
const fasta = @import("fasta-lib.zig");
const Record = records.Record;

const Args = struct {
    fileName: []const u8 = "",
    output: ?[]const u8 = null,

    pub fn parseArgs(argsList: []const [:0]const u8) !Args {
        var args = Args{};
        for (argsList, 0..) |arg, idx| {
            if (strings.equals(arg, "-f")) {
                args.fileName = @as([]const u8, argsList[idx + 1]);
            }
            if (strings.equals(arg, "-o")) {
                args.output = @as([]const u8, argsList[idx + 1]);
            }
            if (strings.equals(arg, "-h")) {
                std.debug.print("Usage: pdb2fasta -f <file> -o <output>\n", .{});
                std.process.exit(0);
            }
        }
        if (strings.equals(args.fileName, "")) {
            std.debug.print("No file specified, please provide a file\n", .{});
            std.process.exit(1);
        }
        return args;
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    // const allocator = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // const args = try std.process.argsAlloc(allocator);
    // defer std.process.argsFree(allocator, args);
    const parsedArgs = try Args.parseArgs(args);

    const file = try std.Io.Dir.cwd().openFile(init.io, parsedArgs.fileName, .{});
    defer file.close(init.io);
    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(init.io, &read_buffer);
    const atoms = try file_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(atoms);

    const converted = try fasta.pdbToFasta(gpa, atoms);
    defer gpa.free(converted);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try stdout_writer.interface.writeAll(converted);
    try stdout_writer.interface.flush();
    if (parsedArgs.output != null) {
        const fastaPath = try std.Io.Dir.cwd().createFile(init.io, parsedArgs.output.?, .{});
        defer fastaPath.close(init.io);
        var write_buffer: [4096]u8 = undefined;
        var fasta_writer = fastaPath.writerStreaming(init.io, &write_buffer);
        try fasta_writer.interface.writeAll(converted);
        try fasta_writer.interface.flush();
    }
}
