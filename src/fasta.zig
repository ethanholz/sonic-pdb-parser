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
                std.os.exit(0);
            }
        }
        if (strings.equals(args.fileName, "")) {
            std.debug.print("No file specified, please provide a file\n", .{});
            std.os.exit(1);
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
    var bufreader = std.io.bufferedReader(file.reader());
    const atoms = try bufreader.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(atoms);

    const converted = try fasta.pdbToFasta(allocator, atoms);
    defer allocator.free(converted);
    _ = try std.io.getStdOut().writer().writeAll(converted);
    if (parsedArgs.output != null) {
        const fastaPath = try std.fs.cwd().createFile(parsedArgs.output.?, .{});
        defer fastaPath.close();
        _ = try fastaPath.writer().writeAll(converted);
    }
}
