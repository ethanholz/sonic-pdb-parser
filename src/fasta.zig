const std = @import("std");
const records = @import("records.zig");
const strings = @import("strings.zig");
const Record = records.Record;

// Handles conversion of 3 letter amino acid codes to 1 letter codes
fn aa3to1(input: []const u8) u8 {
    // zig fmt: off
    const terms = [_][]const u8{
        "ALAA",
        "VALV",
        "PHEF",
        "PROP",
        "METM",
        "ILEI",
        "LEUL",
        "ASPD",
        "GLUE",
        "LYSK",
        "ARGR",
        "SERS",
        "THRT",
        "TYRY",
        "HISH",
        "CYSC",
        "ASNN",
        "GLNQ",
        "TRPW",
        "GLYG",
    };
    // zig fmt: on
    inline for (terms) |term| {
        if (std.mem.eql(u8, term[0..3], input)) {
            return term[3];
        }
    }
    return 'X';
}

test "aa3to1" {
    const input: []const u8 = "ALA";
    const out = aa3to1(input);
    try std.testing.expectEqual(out, 'A');
    const input2: []const u8 = "OTO";
    const out2 = aa3to1(input2);
    try std.testing.expectEqual(out2, 'X');
}

fn handleRecord(writer: anytype, record: Record, prevChainID: *u8) !void {
    const name = record.name();
    const altLoc = record.altLoc();
    const resName = record.resName();
    const chainID = record.chainID();
    switch (record) {
        .hetatm, .atom => {
            // zig fmt: off
                if (
                    (altLoc != null and altLoc != 'A') or 
                    (name != null and !std.mem.eql(u8, name.?, "CA")) or
                    (record == .hetatm and resName != null and std.mem.eql(u8, resName.?, "MSE"))) {
                    return;
                }
                // zig fmt: on
            if (prevChainID.* != chainID) {
                prevChainID.* = chainID.?;
                try writer.print(">pdb:{c}\n", .{chainID.?});
            }
            try writer.print("{c}", .{aa3to1(record.resName().?)});
        },
        else => {},
    }
}

pub fn pdbToFasta(allocator: std.mem.Allocator, lines: []const u8) ![]const u8 {
    var builder = std.ArrayList(u8).init(allocator);
    const writer = builder.writer();
    var prevChainID: u8 = 0;
    var recordNumber: u32 = 0;
    var input = std.mem.tokenizeScalar(u8, lines, '\n');
    const end = std.mem.readInt(u48, "END   ", .little);
    while (input.next()) |line| {
        if (line.len < 6) continue;
        const tag_int = std.mem.readInt(u48, line[0..6], .little);
        if (tag_int == end) break;
        const tag = std.meta.intToEnum(records.RecordType, tag_int) catch continue;
        var record = try Record.parse(line, tag, recordNumber, allocator);
        defer record.free(allocator);
        recordNumber = record.serial();
        if (record == .endmdl) break;
        try handleRecord(writer, record, &prevChainID);
    }
    return try builder.toOwnedSlice();
}

// Handles the conversion of a list of records to a fasta file
pub fn recordsToFasta(allocator: std.mem.Allocator, input: std.ArrayList(Record)) ![]const u8 {
    var builder = std.ArrayList(u8).init(allocator);
    const writer = builder.writer();
    var prevChainID: u8 = 0;
    for (input.items) |record| {
        if (record == .endmdl) break;
        try handleRecord(writer, record, &prevChainID);
    }
    return try builder.toOwnedSlice();
}

test "recordsToFasta" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var file = try std.fs.cwd().openFile("tests/1mbs.pdb", .{});
    defer file.close();
    var bufreader = std.io.bufferedReader(file.reader());
    var atoms = try records.PDBReader(bufreader.reader(), allocator);
    defer atoms.deinit();
    const slice = try recordsToFasta(allocator, atoms);
    defer allocator.free(slice);
    for (atoms.items) |*atom| {
        atom.free(allocator);
    }
    try std.testing.expectEqualStrings(">pdb:A\nGLSDGEWHLVLNVWGKVETDLAGHGQEVLIRLFKSHPETLEKFDKFKHLKSEDDMRRSEDLRKHGNTVLTALGGILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSKHPAEFGADAQAAMKKALELFRNDIAAKYKELGFHG", slice);
}

const Args = struct {
    fileName: []const u8 = "",
    output: []const u8 = "out.fasta",

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const parsedArgs = try Args.parseArgs(args);

    const file = try std.fs.cwd().openFile(parsedArgs.fileName, .{});
    defer file.close();
    var bufreader = std.io.bufferedReader(file.reader());
    var atoms = try records.PDBReader(bufreader.reader(), allocator);
    defer atoms.deinit();
    const fasta = try std.fs.cwd().createFile(parsedArgs.output, .{});
    // const converted = try pdbToFasta(allocator, atoms);
    const converted = try recordsToFasta(allocator, atoms);
    _ = try fasta.writeAll(converted);
    for (atoms.items) |*atom| {
        atom.free(allocator);
    }
    allocator.free(converted);
}
