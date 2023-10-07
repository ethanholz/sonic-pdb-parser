const std = @import("std");

const strings = @import("strings.zig");

const string = []const u8;
const char = u8;

// Reads in a PDB file and converts them to an ArrayList of atoms
pub fn PDBReader(fileBuf: []u8, allocator: std.mem.Allocator) !std.ArrayList(AtomRecord) {
    var atoms = std.ArrayList(AtomRecord).init(allocator);
    var lines = std.mem.splitSequence(u8, fileBuf, "\n");
    var recordNumber: u32 = 0;
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line[0..3], "END")) {
            break;
        }
        if (!strings.equals(line[0..4], "ATOM")) {
            continue;
        }
        var record = try AtomRecord.parse(line, recordNumber, allocator);
        recordNumber = record.serial;
        try atoms.append(record);
    }
    return atoms;
}

/// Holds the performance data for a single run
/// Also handle writing the data to a csv file
pub const RunRecord = struct {
    /// The run number
    run: u64,
    /// The time in nanoseconds
    time: u64,
    /// The file name
    file: string,

    pub fn writeCSVLine(self: *RunRecord, allocator: std.mem.Allocator, file: std.fs.File) !void {
        const runPrint = try std.fmt.allocPrint(allocator, "{d},{d},{s}\n", .{ self.run, self.time, self.file });
        defer allocator.free(runPrint);
        _ = try file.write(runPrint);
    }

    pub fn writeCSVHeader(file: std.fs.File) !void {
        const fields = @typeInfo(RunRecord).Struct.fields;
        const len = fields.len;
        inline for (fields, 0..) |field, idx| {
            std.debug.print("{s}\n", .{field.name});
            _ = try file.write(field.name);
            if (idx == len - 1) {
                break;
            }
            _ = try file.write(",");
        }
        _ = try file.write("\n");
    }
};

pub const AtomRecord = struct {
    record: string = undefined,
    serial: u32 = undefined,
    name: string = undefined,
    altLoc: ?char = null,
    resName: string = undefined,
    chainID: char = undefined,
    resSeq: u16 = undefined,
    iCode: ?char = null,
    x: f32 = undefined,
    y: f32 = undefined,
    z: f32 = undefined,
    occupancy: f32 = undefined,
    tempFactor: f32 = undefined,
    element: string = undefined,
    charge: string = undefined,
    entry: string = undefined,

    pub fn toJson(self: *AtomRecord, list: *std.ArrayList(u8)) ![]u8 {
        _ = try std.json.stringify(self, .{}, list.writer());
        return list.items;
    }

    pub fn parse(line: []const u8, index: u32, allocator: std.mem.Allocator) !AtomRecord {
        var parsedLine = Line.new(line);
        var atom = try parsedLine.convertToAtomRecord(index, allocator);
        // std.debug.print("{s}\n", .{atom.record});
        return atom;
    }

    pub const print = printAll;

    pub fn printAll(self: *AtomRecord) !void {
        const fields = @typeInfo(AtomRecord).Struct.fields;
        inline for (fields) |field| {
            switch (field.type) {
                u8, u16, u32, u64, i8, i16, i32, i64, f32, f64 => {
                    std.debug.print("{s}:{d} ", .{ field.name, @field(self, field.name) });
                },
                string => {
                    var str: string = @field(self, field.name);
                    if (str.len != 0) {
                        std.debug.print("{s}:{s} ", .{ field.name, str });
                    }
                },
                ?string => {
                    var str: ?string = @field(self, field.name);
                    if (str) |s| {
                        std.debug.print("{s}:{s} ", .{ field.name, s });
                    } else {
                        std.debug.print("nope", .{});
                    }
                },
                ?u8 => {
                    if (@field(self, field.name) != null) {
                        std.debug.print("{s}:{?d} ", .{ field.name, @field(self, field.name) });
                    }
                },
                else => std.debug.print("unknown type {}\n", .{field.type}),
            }
        }
        std.debug.print("\n", .{});
    }

    pub fn free(self: *AtomRecord, allocator: std.mem.Allocator) !void {
        allocator.free(self.record);
        allocator.free(self.name);
        allocator.free(self.resName);
        allocator.free(self.element);
        allocator.free(self.charge);
        allocator.free(self.entry);
    }
};

const Line = struct {
    record: [6]u8,
    serial: [5]u8,
    _space: [1]u8,
    name: [4]u8,
    altLoc: [1]u8,
    resName: [3]u8,
    _space2: [1]u8,
    chainID: [1]u8,
    resSeq: [4]u8,
    iCode: [1]u8,
    _space3: [3]u8,
    x: [8]u8,
    y: [8]u8,
    z: [8]u8,
    occupancy: [6]u8,
    tempFactor: [6]u8,
    _space4: [10]u8,
    element: [2]u8,
    charge: [2]u8,

    fn new(line: []const u8) Line {
        var ret: Line = undefined;
        comptime var idx = 0;
        const fields = @typeInfo(Line).Struct.fields;
        inline for (fields) |field| {
            comptime var len = @typeInfo(field.type).Array.len;
            if (idx + len > line.len) {
                break;
            }
            @field(ret, field.name) = line[idx .. idx + len].*;
            idx += len;
        }
        return ret;
    }

    fn convertToAtomRecord(self: *Line, serialIndex: u32, allocator: std.mem.Allocator) !AtomRecord {
        var atom: AtomRecord = undefined;
        // var parsed = strings.removeSpaces(&self.record);
        atom.record = try strings.removeSpacesAlloc(&self.record, allocator);
        atom.serial = std.fmt.parseInt(u32, strings.removeSpaces(&self.serial), 10) catch serialIndex + 1;
        atom.name = try strings.removeSpacesAlloc(&self.name, allocator);
        atom.altLoc = if (self.altLoc[0] == 32) null else self.altLoc[0];
        atom.resName = try strings.removeSpacesAlloc(&self.resName, allocator);
        atom.chainID = self.chainID[0];
        atom.resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(&self.resSeq), 10);
        atom.iCode = if (self.iCode[0] == 32) null else self.iCode[0];
        atom.x = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.x));
        atom.y = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.y));
        atom.z = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.z));
        atom.occupancy = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.occupancy));
        atom.tempFactor = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.tempFactor));
        atom.element = try strings.removeSpacesAlloc(&self.element, allocator);
        atom.charge = try strings.removeSpacesAlloc(&self.charge, allocator);
        // atom.charge = try strings.removeSpacesAlloc(&self.charge, allocator);
        atom.entry = try strings.removeSpacesAlloc(&self._space4, allocator);
        return atom;
    }
};

test "convert to atoms" {
    const line = "ATOM     17  NE2 GLN     2      25.562  32.733   1.806  1.00 19.49      1UBQ";
    var parsedLine = Line.new(line);
    try std.testing.expect(strings.equals("ATOM  ", &parsedLine.record));
    try std.testing.expect(strings.equals("   17", &parsedLine.serial));
    try std.testing.expect(strings.equals(" NE2", &parsedLine.name));
    try std.testing.expect(strings.equals(" ", &parsedLine.altLoc));
    try std.testing.expect(strings.equals("GLN", &parsedLine.resName));
    try std.testing.expect(strings.equals("   2", &parsedLine.resSeq));
    try std.testing.expect(strings.equals("  25.562", &parsedLine.x));
    try std.testing.expect(strings.equals("  32.733", &parsedLine.y));
    try std.testing.expect(strings.equals("   1.806", &parsedLine.z));
    try std.testing.expect(strings.equals("  1.00", &parsedLine.occupancy));
    try std.testing.expect(strings.equals(" 19.49", &parsedLine.tempFactor));
    try std.testing.expect(strings.equals("      1UBQ", &parsedLine._space4));
    var atom = try parsedLine.convertToAtomRecord();
    try std.testing.expect(strings.equals("ATOM", atom.record));
    try std.testing.expect(17 == atom.serial);
    try std.testing.expect(strings.equals("NE2", atom.name));
    try std.testing.expect(strings.equals("GLN", atom.resName));
    try std.testing.expect(2 == atom.resSeq);
    try std.testing.expect(25.562 == atom.x);
    try std.testing.expect(32.733 == atom.y);
    try std.testing.expect(1.806 == atom.z);
    try std.testing.expect(1.00 == atom.occupancy);
    try std.testing.expect(19.49 == atom.tempFactor);
    try std.testing.expect(strings.equals("1UBQ", atom.entry));
}

test "convert to atoms drude" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var parsedLine = Line.new(line);
    try std.testing.expect(strings.equals("ATOM  ", &parsedLine.record));
    try std.testing.expect(strings.equals("    1", &parsedLine.serial));
    try std.testing.expect(strings.equals(" N  ", &parsedLine.name));
    try std.testing.expect(strings.equals(" ", &parsedLine.altLoc));
    try std.testing.expect(strings.equals("MET", &parsedLine.resName));
    try std.testing.expect(strings.equals("   1", &parsedLine.resSeq));
    try std.testing.expect(strings.equals("  34.774", &parsedLine.x));
    try std.testing.expect(strings.equals("  28.332", &parsedLine.y));
    try std.testing.expect(strings.equals("  51.752", &parsedLine.z));
    try std.testing.expect(strings.equals("  1.00", &parsedLine.occupancy));
    try std.testing.expect(strings.equals("  0.00", &parsedLine.tempFactor));
    try std.testing.expect(strings.equals("      PROA", &parsedLine._space4));
    var atom = try parsedLine.convertToAtomRecord();
    try std.testing.expect(strings.equals("ATOM", atom.record));
    try std.testing.expect(1 == atom.serial);
    try std.testing.expect(strings.equals("N", atom.name));
    try std.testing.expect(strings.equals("MET", atom.resName));
    try std.testing.expect(1 == atom.resSeq);
    try std.testing.expect(34.774 == atom.x);
    try std.testing.expect(28.332 == atom.y);
    try std.testing.expect(51.752 == atom.z);
    try std.testing.expect(1.00 == atom.occupancy);
    try std.testing.expect(0.00 == atom.tempFactor);
    try std.testing.expect(strings.equals("PROA", atom.entry));
}

test "convert to atoms multi-line" {
    const lines = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA\nATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var atoms = std.ArrayList(AtomRecord).init(std.testing.allocator);
    defer atoms.deinit();
    var split = std.mem.splitSequence(u8, lines, "\n");
    while (split.next()) |line| {
        var parsedLine = Line.new(line);
        var atom = try parsedLine.convertToAtomRecord();
        try atoms.append(atom);
    }
    try std.testing.expect(2 == atoms.items.len);
    try std.testing.expect(strings.equals("ATOM", atoms.items[0].record));
    try std.testing.expect(strings.equals("ATOM", atoms.items[1].record));
}

test "toJson" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var parsedLine = Line.new(line);
    var atom = try parsedLine.convertToAtomRecord();
    var arrayList = std.ArrayList(u8).init(std.testing.allocator);
    defer arrayList.deinit();
    var out = try atom.toJson(&arrayList);
    std.debug.print("\n{s}\n", .{out});
}
