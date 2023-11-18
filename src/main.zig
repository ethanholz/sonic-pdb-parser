const std = @import("std");
const fs = std.fs;

const string = []const u8;
const char = u8;

const strings = @import("strings.zig");
const AtomRecord = @import("records.zig").AtomRecord;
const RunRecord = @import("records.zig").RunRecord;
const PDBReader = @import("records.zig").PDBReader;

test {
    // this causes 'zig build test' to test any referenced files
    _ = @import("records.zig");
}

const Args = struct {
    runs: u64 = 100,
    fileName: string = "",
    output: string = "times.csv",

    pub fn parseArgs(argsList: [][:0]u8) !Args {
        var args = Args{};
        for (argsList, 0..) |arg, idx| {
            if (strings.equals(arg, "-r")) {
                args.runs = try std.fmt.parseInt(u64, argsList[idx + 1], 10);
            }
            if (strings.equals(arg, "-f")) {
                args.fileName = @as(string, argsList[idx + 1]);
            }
            if (strings.equals(arg, "-o")) {
                args.output = @as(string, argsList[idx + 1]);
            }
            if (strings.equals(arg, "-h")) {
                std.debug.print("Usage: exe -r <runs> -f <file> -o <output>\n", .{});
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const parsedArgs = try Args.parseArgs(args);

    const file = try fs.cwd().openFile(parsedArgs.fileName, .{});
    defer file.close();

    if (parsedArgs.runs == 1) {
        var bufreader = std.io.bufferedReader(file.reader());
        var atoms = try PDBReader(bufreader.reader(), allocator);
        defer atoms.deinit();
        for (atoms.items) |*atom| {
            std.debug.print("{}\n", .{atom});
        }
        std.os.exit(0);
    }

    var timer = try std.time.Timer.start();
    var times = try std.ArrayList(u64).initCapacity(allocator, parsedArgs.runs);
    defer times.deinit();
    var sum: u64 = 0;
    const csv = try fs.cwd().createFile(parsedArgs.output, .{});
    defer csv.close();
    try RunRecord.writeCSVHeader(csv);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    for (0..parsedArgs.runs) |i| {
        defer {
            _ = arena.reset(.retain_capacity);
            file.seekTo(0) catch @panic("file error");
        }
        timer.reset();
        var bufreader = std.io.bufferedReader(file.reader());
        _ = try PDBReader(bufreader.reader(), arenaAllocator);
        var elapsed = timer.read();
        try times.append(elapsed);
        var runRecord: RunRecord = RunRecord{ .run = i + 1, .time = elapsed, .file = parsedArgs.fileName };
        try runRecord.writeCSVLine(csv);
        sum += elapsed;
        std.debug.print("Run {} Complete\n", .{i});
    }
    var average: f32 = @floatFromInt(sum / parsedArgs.runs);
    var sumF: f32 = @floatFromInt(sum);
    std.debug.print("sum: {d:.6}s\nparse average: {d:.6} s\n", .{ sumF / 1e+9, average / 1e+9 });
}
