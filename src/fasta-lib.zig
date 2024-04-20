const std = @import("std");
const strings = @import("strings");
const records = @import("sonic");
const Record = records.Record;

const newTerms = std.ComptimeStringMap(u8, .{
    .{ "ALA", 'A' },
    .{ "VAL", 'V' },
    .{ "PHE", 'F' },
    .{ "PRO", 'P' },
    .{ "MET", 'M' },
    .{ "ILE", 'I' },
    .{ "LEU", 'L' },
    .{ "ASP", 'D' },
    .{ "GLU", 'E' },
    .{ "LYS", 'K' },
    .{ "ARG", 'R' },
    .{ "SER", 'S' },
    .{ "THR", 'T' },
    .{ "TYR", 'Y' },
    .{ "HIS", 'H' },
    .{ "CYS", 'C' },
    .{ "ASN", 'N' },
    .{ "GLN", 'Q' },
    .{ "TRP", 'W' },
    .{ "GLY", 'G' },
});

pub inline fn aa3to1(input: []const u8) u8 {
    return newTerms.get(input) orelse 'X';
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
            // const char = aa3to1(record.resName().?);
            // if (char == 'X') std.debug.print("Unknown amino acid: {s}\n", .{record.resName().?});
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
        if (record == .endmdl) break;
        recordNumber = record.serial();
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

// test "recordsToFasta" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();
//     var file = try std.fs.cwd().openFile("tests/1mbs.pdb", .{});
//     defer file.close();
//     var bufreader = std.io.bufferedReader(file.reader());
//     var atoms = try records.PDBReader(bufreader.reader(), allocator);
//     defer atoms.deinit();
//     const slice = try recordsToFasta(allocator, atoms);
//     defer allocator.free(slice);
//     for (atoms.items) |*atom| {
//         atom.free(allocator);
//     }
//     try std.testing.expectEqualStrings(">pdb:A\nGLSDGEWHLVLNVWGKVETDLAGHGQEVLIRLFKSHPETLEKFDKFKHLKSEDDMRRSEDLRKHGNTVLTALGGILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSKHPAEFGADAQAAMKKALELFRNDIAAKYKELGFHG", slice);
// }
