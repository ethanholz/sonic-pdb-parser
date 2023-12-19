const std = @import("std");
const testing = std.testing;
const testalloc = testing.allocator;

const strings = @import("strings.zig");

const string = []const u8;
const char = u8;

/// Reads in a PDB file and converts them to an ArrayList of records
pub fn PDBReader(reader: anytype, allocator: std.mem.Allocator) !std.ArrayList(Record) {
    var records = std.ArrayList(Record).init(allocator);
    var recordNumber: u32 = 0;
    // PDB lines are should not be more than 80 characters long
    // Some of the CHARMM files are longer
    var buf: [90]u8 = undefined;
    const end = std.mem.readInt(u48, "END   ", .little);
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (line.len < 6) continue;
        const tag_int = std.mem.readInt(u48, line[0..6], .little);
        if (tag_int == end) break;
        const tag = std.meta.intToEnum(RecordType, tag_int) catch continue;
        // TODO: Add switch to handle connect records
        const record = try Record.parse(line, tag, recordNumber, allocator);
        recordNumber = record.serial();
        try records.append(record);
    }
    return records;
}

/// Holds the performance data for a single run.
/// Also handle writing the data to a CSV file
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

/// Represents a CONECT record
pub const ConnectRecord = struct {
    serial: u32 = undefined,
    serial1: u32 = undefined,
    serial2: ?u32 = null,
    serial3: ?u32 = null,
    serial4: ?u32 = null,
};

/// Represents a TER record
pub const TermRecord = struct {
    serial: u32,
    resName: string,
    chainID: u8,
    resSeq: u16,
    iCode: ?u8,

    pub fn free(self: *TermRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.resName);
    }
};

/// Represents an ATOM or HETATM record
pub const AtomRecord = struct {
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

    /// Frees all the strings in the struct
    pub fn free(self: *AtomRecord, allocator: std.mem.Allocator) void {
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
        allocator.free(self.resName);
    }
};

/// Represents a MODEL record
pub const ModelRecord = struct {
    serial: u32 = undefined,
};

// zig fmt: off
/// An enum derived of possible records in a PDB file
pub const RecordType = enum(u48) {
    atom =    std.mem.readInt(u48, "ATOM  ", .little),
    hetatm =  std.mem.readInt(u48, "HETATM", .little),
    term =    std.mem.readInt(u48, "TER   ", .little),
    connect = std.mem.readInt(u48, "CONECT", .little),
    model =   std.mem.readInt(u48, "MODEL ", .little),
};
// zig fmt: on

/// A union of all possible records in a PDB file
pub const Record = union(RecordType) {
    /// An ATOM record
    atom: AtomRecord,
    /// A HETATM record
    hetatm: AtomRecord,
    /// A TER record
    term: TermRecord,
    /// A CONECT record
    connect: ConnectRecord,
    /// A MODEL record
    model: ModelRecord,

    /// Parses a line into a record
    pub fn parse(
        raw_line: []const u8,
        tag: RecordType,
        index: u32,
        allocator: std.mem.Allocator,
    ) !Record {
        var cl: *const ConnectLine = undefined;
        var line: *const Line = undefined;
        var ml: *const ModelLine = undefined;
        if (std.mem.eql(u8, raw_line[0..6], "CONECT")) {
            cl = ConnectLine.new(raw_line);
        } else if (std.mem.eql(u8, raw_line[0..6], "MODEL ")) {
            ml = ModelLine.new(raw_line);
        } else {
            line = Line.new(raw_line);
        }
        // const line = Line.new(raw_line);
        const record: Record = switch (tag) {
            inline .atom, .hetatm => |t| @unionInit(
                Record,
                @tagName(t),
                try line.convertToAtomRecord(index, raw_line.len, allocator),
            ),
            .term => .{
                .term = try line.convertToTermRecord(allocator),
            },
            .model => .{
                .model = try ml.convertToModelRecord(),
            },
            .connect => .{
                .connect = try cl.convertToConnectRecord(raw_line.len),
            },
        };

        return record;
    }

    /// Returns a record's chain ID if it has one
    pub fn chainID(self: Record) ?char {
        return switch (self) {
            .atom, .hetatm => |payload| payload.chainID,
            else => null,
        };
    }

    /// Returns a record's alternate location if it has one
    pub fn altLoc(self: Record) ?char {
        return switch (self) {
            .atom, .hetatm => |payload| payload.altLoc,
            else => null,
        };
    }

    /// Returns a record's element if it has one
    pub fn name(self: Record) ?string {
        return switch (self) {
            .atom, .hetatm => |payload| payload.name,
            else => null,
        };
    }

    /// Returns a record's residue name if it has one
    pub fn resName(self: Record) ?string {
        return switch (self) {
            .atom, .hetatm => |payload| payload.resName,
            .term => |payload| payload.resName,
            else => null,
        };
    }

    /// Returns a record's serial number
    pub fn serial(self: Record) u32 {
        return switch (self) {
            .term => |payload| payload.serial,
            .atom, .hetatm => |payload| payload.serial,
            .connect => |payload| payload.serial,
            .model => |payload| payload.serial,
        };
    }

    /// This formatter allows for printing an atom from any print() method. When {json} is passed, it prints json.
    pub fn format(
        self: Record,
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

    /// Calls free on a record if it has any allocated memory
    pub fn free(self: *Record, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .atom, .hetatm => |*atom| atom.free(allocator),
            .term => |*ter| ter.free(allocator),
            .model, .connect => return,
        }
    }
};

const ModelLine = extern struct {
    record: [6]u8,
    _space: [5]u8,
    serial: [4]u8,

    fn new(line: []const u8) *const ModelLine {
        return @ptrCast(line.ptr);
    }

    fn convertToModelRecord(self: *const ModelLine) !ModelRecord {
        return .{
            .serial = try std.fmt.parseInt(u32, strings.removeSpaces(&self.serial), 10),
        };
    }
};

const ConnectLine = extern struct {
    record: [6]u8,
    serial: [5]u8,
    serial1: [5]u8,
    serial2: [5]u8,
    serial3: [5]u8,
    serial4: [5]u8,

    fn new(line: []const u8) *const ConnectLine {
        return @ptrCast(line.ptr);
    }
    fn convertToConnectRecord(self: *const ConnectLine, len: usize) !ConnectRecord {
        var connect: ConnectRecord = ConnectRecord{};
        connect.serial = try std.fmt.parseInt(u32, strings.removeSpaces(&self.serial), 10);
        if (len > 11) {
            connect.serial1 = try std.fmt.parseInt(u32, strings.removeSpaces(&self.serial1), 10);
            if (len > 16) {
                connect.serial2 = std.fmt.parseInt(u32, strings.removeSpaces(&self.serial2), 10) catch null;
            }
            if (len > 21) {
                connect.serial3 = std.fmt.parseInt(u32, strings.removeSpaces(&self.serial3), 10) catch null;
            }
            if (len > 26) {
                connect.serial4 = std.fmt.parseInt(u32, strings.removeSpaces(&self.serial4), 10) catch null;
            }
        }
        return connect;
    }
};

test "Connect Line" {
    const line = "CONECT  413  412  414                                                           ";
    var parseLine = ConnectLine.new(line);
    const record = try parseLine.convertToConnectRecord(line.len);
    try expectEqual(413, record.serial);
    try expectEqual(412, record.serial1);
    try expectEqual(414, record.serial2);
    try expectEqual(null, record.serial3);
    try expectEqual(null, record.serial4);
}

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

    fn convertToTermRecord(self: *const Line, allocator: std.mem.Allocator) !TermRecord {
        return .{
            .serial = try std.fmt.parseInt(u32, strings.removeSpaces(&self.serial), 10),
            .resName = try allocator.dupe(u8, strings.removeSpaces(&self.resName)),
            .chainID = self.chainID[0],
            .resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(&self.resSeq), 10),
            .iCode = if (self.iCode[0] == 32) null else self.iCode[0],
        };
    }

    fn convertToAtomRecord(self: *const Line, serialIndex: u32, len: usize, allocator: std.mem.Allocator) !AtomRecord {
        var atom: AtomRecord = AtomRecord{};
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
        const entry = strings.removeSpaces(&self._space4);
        if (entry.len != 0) {
            atom.entry = try allocator.dupe(u8, entry);
        }
        if (len > 76) {
            atom.element = try allocator.dupe(u8, strings.removeSpaces(&self.element));
            if (len == 80) {
                atom.charge = try allocator.dupe(u8, strings.removeSpaces(&self.charge));
            }
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
    var atom = try parsedLine.convertToAtomRecord(1, line.len, testalloc);
    defer atom.free(testalloc);
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
    try expectEqual(null, atom.element);
    try expectEqual(null, atom.charge);
    try testing.expectEqualStrings("1UBQ", atom.entry.?);
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
    var atom = try parsedLine.convertToAtomRecord(0, line.len, testalloc);
    defer atom.free(testalloc);
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
    try expectEqual(null, atom.element);
    try expectEqual(null, atom.charge);
    try testing.expectEqualStrings("PROA", atom.entry.?);
}

// TODO: Update test to handle different lines, rather than the same
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
        const atom = try parsedLine.convertToAtomRecord(0, line.len, testalloc);
        try atoms.append(atom);
    }
    try expectEqual(2, atoms.items.len);
    for (atoms.items) |atom| {
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
        try expectEqual(null, atom.element);
        try expectEqual(null, atom.charge);
        try testing.expectEqualStrings("PROA", atom.entry.?);
    }
}

test "toJson" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var record = try Record.parse(line, .atom, 0, testalloc);
    defer record.free(testalloc);

    // use a format specifier to print json. yet another way to avoid allocting :^)
    std.debug.print("\n{json}\n", .{record});
}
