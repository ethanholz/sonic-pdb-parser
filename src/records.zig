const std = @import("std");
const testing = std.testing;
const testalloc = testing.allocator;

const strings = @import("strings.zig");

const string = []const u8;
const char = u8;

// Reads in a PDB file and converts them to an ArrayList of atoms
pub fn PDBReader(reader: anytype, allocator: std.mem.Allocator) !std.ArrayList(AtomRecord) {
    var atoms = std.ArrayList(AtomRecord).init(allocator);
    var recordNumber: u32 = 0;
    // PDB lines are no more than 80 characters long
    var buf: [80]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (std.mem.eql(u8, line[0..3], "END")) {
            break;
        }
        if (!strings.equals(line[0..4], "ATOM")) {
            continue;
        }
        const record = try AtomRecord.parse(line, recordNumber, allocator);
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

    // there is no need to allocate here. you can print directly to the file.
    pub fn writeCSVLine(self: *RunRecord, file: std.fs.File) !void {
        try file.writer().print("{d},{d},{s}\n", .{ self.run, self.time, self.file });
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
    element: ?string = null,
    charge: ?string = null,
    entry: ?string = null,

    pub fn toJson(self: AtomRecord, list: *std.ArrayList(u8)) ![]u8 {
        _ = try std.json.stringify(self, .{}, list.writer());
        return list.items;
    }

    pub fn parse(line: []const u8, index: u32, allocator: std.mem.Allocator) !AtomRecord {
        const len = line.len;
        const parsedLine = Line.new(line);
        const atom = try parsedLine.convertToAtomRecord(index, len, allocator);
        return atom;
    }

    // this formatter allows for printing an atom from any print() method.
    // and when fmt == "json", it writes json.
    pub fn format(
        self: AtomRecord,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (comptime std.mem.eql(u8, fmt, "json")) {
            _ = try std.json.stringify(self, .{}, writer);
        } else {
            const fields = @typeInfo(AtomRecord).Struct.fields;
            inline for (fields) |field| {
                const fmt2 = switch (@typeInfo(field.type)) {
                    .Optional => |info| if (comptime std.meta.trait.isZigString(info.child))
                        "{?s}"
                    else
                        "{?}",
                    .Float => "{d:.3}",
                    .Int => "{}",
                    else => if (comptime std.meta.trait.isZigString(field.type))
                        "{s}"
                    else
                        "{}",
                };
                try writer.print("{s}:" ++ fmt2 ++ " ", .{ field.name, @field(self, field.name) });
            }
        }
    }

    pub fn free(self: *AtomRecord, allocator: std.mem.Allocator) void {
        // allocator.free(self.charge);
        // allocator.free(self.element);
        if (self.charge != null) {
            allocator.free(self.charge.?);
        }
        if (self.element != null) {
            allocator.free(self.element.?);
        }
        if (self.entry != null) {
            allocator.free(self.entry.?);
        }
        allocator.free(self.name);
        allocator.free(self.record);
        allocator.free(self.resName);
    }
};

// i've made this an extern struct which has well defined memory layout
// unlike normal zig structs.  i did this because all its fields are arrays
// which are extern compatible.  this means you can bitcast to/from an array.
// however when i tried that i noticed the test data was shorter than 80 bytes
// and caused the following error.  i've left the commented out code below
// which led to this.  my solution was to pointer cast.  this prevents the oob
// read and will likely be a little faster, returning 8 bytes vs 80 bytes.
const Line = extern struct {
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

    // i've left this in just to show what i might otherwise do.  if uncommented
    // it will produce the following error
    //   : error: thread 681909 panic: index out of bounds: index 80, len 76
    // fn new(line: []const u8) Line {
    //     return @bitCast(line[0..@sizeOf(Line)].*);
    fn new(line: []const u8) *const Line {
        return @ptrCast(line.ptr);
    }

    fn convertToAtomRecord(self: *const Line, serialIndex: u32, len: usize, allocator: std.mem.Allocator) !AtomRecord {
        var atom: AtomRecord = undefined;
        atom.record = try allocator.dupe(u8, strings.removeSpaces(&self.record));
        atom.serial = std.fmt.parseInt(u32, strings.removeSpaces(&self.serial), 10) catch serialIndex + 1;
        atom.name = try allocator.dupe(u8, strings.removeSpaces(&self.name));
        atom.altLoc = if (self.altLoc[0] == 32) null else self.altLoc[0];
        atom.resName = try allocator.dupe(u8, strings.removeSpaces(&self.resName));
        atom.chainID = self.chainID[0];
        atom.resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(&self.resSeq), 10);
        atom.iCode = if (self.iCode[0] == 32) null else self.iCode[0];
        atom.x = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.x));
        atom.y = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.y));
        atom.z = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.z));
        atom.occupancy = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.occupancy));
        atom.tempFactor = try std.fmt.parseFloat(f32, strings.removeSpaces(&self.tempFactor));
        var entry = strings.removeSpaces(&self._space4);
        if (entry.len != 0) {
            atom.entry = try allocator.dupe(u8, entry);
        }
        if (len > 76) {
            atom.element = try allocator.dupe(u8, strings.removeSpaces(&self.element));
            if (len == 80) {
                atom.charge = try allocator.dupe(u8, strings.removeSpaces(&self.charge));
            } else {
                atom.charge = null;
            }
        } else {
            atom.element = null;
            atom.charge = null;
        }
        return atom;
    }
};

// i noticed you weren't able to see the difference between strings.  this is why
// i've used expectEqualStrings() below.  and this helper will also print out
// the expected vs actual values when they differ.
fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected, actual); // peer type resolution
    return testing.expectEqual(@as(T, expected), actual);
}

test "convert to atoms" {
    const line = "ATOM     17  NE2 GLN     2      25.562  32.733   1.806  1.00 19.49      1UBQ";
    const parsedLine = Line.new(line);
    try testing.expectEqualStrings("ATOM  ", &parsedLine.record);
    try testing.expectEqualStrings("   17", &parsedLine.serial);
    try testing.expectEqualStrings(" NE2", &parsedLine.name);
    try testing.expectEqualStrings(" ", &parsedLine.altLoc);
    try testing.expectEqualStrings("GLN", &parsedLine.resName);
    try testing.expectEqualStrings("   2", &parsedLine.resSeq);
    try testing.expectEqualStrings("  25.562", &parsedLine.x);
    try testing.expectEqualStrings("  32.733", &parsedLine.y);
    try testing.expectEqualStrings("   1.806", &parsedLine.z);
    try testing.expectEqualStrings("  1.00", &parsedLine.occupancy);
    try testing.expectEqualStrings(" 19.49", &parsedLine.tempFactor);
    try testing.expectEqualStrings("      1UBQ", &parsedLine._space4);
    var atom = try parsedLine.convertToAtomRecord(1, testalloc);
    defer atom.free(testalloc);
    try testing.expectEqualStrings("ATOM", atom.record);
    // try std.testing.expect(17 == atom.serial);
    try expectEqual(17, atom.serial);
    try testing.expectEqualStrings("NE2", atom.name);
    try testing.expectEqualStrings("GLN", atom.resName);
    try std.testing.expect(2 == atom.resSeq);
    try expectEqual(2, atom.resSeq);
    try expectEqual(25.562, atom.x);
    try expectEqual(32.733, atom.y);
    try expectEqual(1.806, atom.z);
    try expectEqual(1.00, atom.occupancy);
    try expectEqual(19.49, atom.tempFactor);
    try testing.expectEqualStrings("1UBQ", atom.entry);
    // this is how you use the format() method from above.
    std.debug.print("{}\n", .{atom});
}

test "convert to atoms drude" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    const parsedLine = Line.new(line);
    try testing.expectEqualStrings("ATOM  ", &parsedLine.record);
    try testing.expectEqualStrings("    1", &parsedLine.serial);
    try testing.expectEqualStrings(" N  ", &parsedLine.name);
    try testing.expectEqualStrings(" ", &parsedLine.altLoc);
    try testing.expectEqualStrings("MET", &parsedLine.resName);
    try testing.expectEqualStrings("   1", &parsedLine.resSeq);
    try testing.expectEqualStrings("  34.774", &parsedLine.x);
    try testing.expectEqualStrings("  28.332", &parsedLine.y);
    try testing.expectEqualStrings("  51.752", &parsedLine.z);
    try testing.expectEqualStrings("  1.00", &parsedLine.occupancy);
    try testing.expectEqualStrings("  0.00", &parsedLine.tempFactor);
    try testing.expectEqualStrings("      PROA", &parsedLine._space4);
    var atom = try parsedLine.convertToAtomRecord(0, testalloc);
    defer atom.free(testalloc);
    try testing.expectEqualStrings("ATOM", atom.record);
    try expectEqual(1, atom.serial);
    try testing.expectEqualStrings("N", atom.name);
    try testing.expectEqualStrings("MET", atom.resName);
    try expectEqual(null, atom.iCode);
    try expectEqual(1, atom.resSeq);
    try expectEqual(34.774, atom.x);
    try expectEqual(28.332, atom.y);
    try expectEqual(51.752, atom.z);
    try expectEqual(1.00, atom.occupancy);
    try expectEqual(0.00, atom.tempFactor);
    try testing.expectEqualStrings("", atom.element);
    try testing.expectEqualStrings("", atom.charge);
    try testing.expectEqualStrings("PROA", atom.entry);
}

// record: string = undefined,
// serial: u32 = undefined,
// name: string = undefined,
// altLoc: ?char = null,
// resName: string = undefined,
// chainID: char = undefined,
// resSeq: u16 = undefined,
// iCode: ?char = null,
// x: f32 = undefined,
// y: f32 = undefined,
// z: f32 = undefined,
// occupancy: f32 = undefined,
// tempFactor: f32 = undefined,
// element: string = undefined,
// charge: string = undefined,
// entry: string = undefined,
test "convert to atoms multi-line" {
    const lines = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA\nATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var atoms = std.ArrayList(AtomRecord).init(testing.allocator);
    defer {
        for (atoms.items) |*atom| atom.free(testalloc);
        atoms.deinit();
    }

    var split = std.mem.splitSequence(u8, lines, "\n");
    while (split.next()) |line| {
        const parsedLine = Line.new(line);
        const atom = try parsedLine.convertToAtomRecord(0, testalloc);
        try atoms.append(atom);
    }
    try expectEqual(2, atoms.items.len);
    try testing.expectEqualStrings("ATOM", atoms.items[0].record);
    try testing.expectEqualStrings("ATOM", atoms.items[1].record);
}

test "toJson" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    const parsedLine = Line.new(line);
    var atom = try parsedLine.convertToAtomRecord(0, testalloc);
    defer atom.free(testalloc);

    // use a format specifier to print json. yet another way to avoid allocting :^)
    std.debug.print("\n{json}\n", .{atom});
}
