const std = @import("std");
const records = @import("sonic");
const strings = @import("strings");
const fasta = @import("fasta-lib.zig");
const Record = records.Record;

const Args = struct {
    fileName: []const u8 = "",
    output: ?[]const u8 = null,

    pub fn parseArgs(argsList: [][:0]u8) !Args {
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
                std.posix.exit(0);
            }
        }
        if (strings.equals(args.fileName, "")) {
            std.debug.print("No file specified, please provide a file\n", .{});
            std.posix.exit(1);
        }
        return args;
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const parsedArgs = try Args.parseArgs(args);

    const file = try std.fs.cwd().openFile(parsedArgs.fileName, .{});
    defer file.close();
    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buffer);
    const atoms = try file_reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(atoms);

    const converted = try fasta.pdbToFasta(allocator, atoms);
    defer allocator.free(converted);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buffer);
    try stdout_writer.interface.writeAll(converted);
    try stdout_writer.interface.flush();
    if (parsedArgs.output != null) {
        const fastaPath = try std.fs.cwd().createFile(parsedArgs.output.?, .{});
        defer fastaPath.close();
        var write_buffer: [4096]u8 = undefined;
        var fasta_writer = fastaPath.writerStreaming(&write_buffer);
        try fasta_writer.interface.writeAll(converted);
        try fasta_writer.interface.flush();
    }
}
