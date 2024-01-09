const std = @import("std");
const testing = std.testing;
const testalloc = testing.allocator;

const strings = @import("strings.zig");

const string = []const u8;
const char = u8;

pub const PDB = struct {
    records: std.ArrayList(Record) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !PDB {
        var pdb = PDB{};
        pdb.records = std.ArrayList(Record).init(allocator);
        pdb.allocator = allocator;
        return pdb;
    }

    pub fn deinit(self: *PDB) void {
        for (self.records.items) |*record| record.free(self.allocator);
        self.records.deinit();
    }

    pub fn read(self: *PDB, reader: anytype) !void {
        var buf: [90]u8 = undefined;
        var recordNumber: u32 = 0;
        const end = std.mem.readInt(u48, "END   ", .little);
        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (line.len < 6) continue;
            const tag_int = std.mem.readInt(u48, line[0..6], .little);
            if (tag_int == end) break;
            const tag = std.meta.intToEnum(RecordType, tag_int) catch continue;
            if (tag == .endmdl) {
                continue;
            }
            // TODO: Add switch to handle connect records
            const record = try Record.parse(line, tag, recordNumber, self.allocator);
            recordNumber = record.serial();
            try self.records.append(record);
        }
    }

    pub fn format(
        self: PDB,
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        for (self.records.items) |record| {
            if (comptime std.mem.eql(u8, fmt, "json")) {
                try writer.print("{json}\n", .{record});
            } else {
                try writer.print("{}\n", .{record});
            }
        }
    }
};

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
        if (tag == .endmdl) {
            continue;
        }
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

    pub fn new(raw_line: []const u8) !ConnectRecord {
        var connect: ConnectRecord = ConnectRecord{};
        connect.serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[6..11]), 10);
        connect.serial1 = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[11..16]), 10);
        if (raw_line.len > 21) {
            connect.serial2 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[16..21]), 10) catch null;
        }
        if (raw_line.len > 26) {
            connect.serial3 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[21..26]), 10) catch null;
        }
        if (raw_line.len > 31) {
            connect.serial4 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[26..31]), 10) catch null;
        }
        return connect;
    }
};

/// Represents a TER record
pub const TermRecord = struct {
    serial: u32,
    resName: string,
    chainID: u8,
    resSeq: u16,
    iCode: ?u8,

    pub fn new(raw_line: []const u8, allocator: std.mem.Allocator) !TermRecord {
        return .{
            .serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[6..11]), 10),
            .resName = try allocator.dupe(u8, strings.removeSpaces(raw_line[17..20])),
            .chainID = raw_line[21],
            .resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(raw_line[22..26]), 10),
            .iCode = if (raw_line[26] == 32) null else raw_line[26],
        };
    }

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

    pub fn new(raw_line: []const u8, index: u32, allocator: std.mem.Allocator) !AtomRecord {
        var atom: AtomRecord = AtomRecord{};
        atom.serial = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[6..11]), 10) catch index + 1;
        atom.name = try allocator.dupe(u8, strings.removeSpaces(raw_line[12..16]));
        atom.altLoc = if (raw_line[16] == 32) null else raw_line[16];
        atom.resName = try allocator.dupe(u8, strings.removeSpaces(raw_line[17..20]));
        atom.chainID = raw_line[21];
        atom.resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(raw_line[22..26]), 10);
        atom.iCode = if (raw_line[26] == 32) null else raw_line[26];
        atom.x = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[30..38]));
        atom.y = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[38..46]));
        atom.z = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[46..54]));
        atom.occupancy = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[54..60]));
        atom.tempFactor = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[60..66]));
        const entry = strings.removeSpaces(raw_line[66..76]);
        if (entry.len != 0) {
            atom.entry = try allocator.dupe(u8, entry);
        }
        if (raw_line.len > 76) {
            const element = strings.removeSpaces(raw_line[76..78]);
            if (element.len != 0) {
                atom.element = try allocator.dupe(u8, element);
            }
            if (raw_line.len == 80) {
                const charge = strings.removeSpaces(raw_line[78..80]);
                if (charge.len != 0) {
                    atom.charge = try allocator.dupe(u8, charge);
                }
            }
        }
        return atom;
    }

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

pub const AnisotropicRecord = struct {
    serial: u32 = undefined,
    name: string = undefined,
    altLoc: ?char = null,
    resName: string = undefined,
    chainID: char = undefined,
    resSeq: u16 = undefined,
    iCode: ?char = null,
    u00: i32 = undefined,
    u11: i32 = undefined,
    u22: i32 = undefined,
    u01: i32 = undefined,
    u02: i32 = undefined,
    u12: i32 = undefined,
    element: ?string = null,
    charge: ?string = null,

    pub fn new(raw_line: []const u8, allocator: std.mem.Allocator) !AnisotropicRecord {
        var anisotropic: AnisotropicRecord = AnisotropicRecord{};
        anisotropic.serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[6..11]), 10);
        anisotropic.name = try allocator.dupe(u8, strings.removeSpaces(raw_line[12..16]));
        anisotropic.altLoc = if (raw_line[16] == 32) null else raw_line[16];
        anisotropic.resName = try allocator.dupe(u8, strings.removeSpaces(raw_line[17..20]));
        anisotropic.chainID = raw_line[21];
        anisotropic.resSeq = try std.fmt.parseInt(u16, strings.removeSpaces(raw_line[22..26]), 10);
        anisotropic.iCode = if (raw_line[26] == 32) null else raw_line[26];
        anisotropic.u00 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[28..35]), 10);
        anisotropic.u11 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[35..42]), 10);
        anisotropic.u22 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[42..49]), 10);
        anisotropic.u01 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[49..56]), 10);
        anisotropic.u02 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[56..63]), 10);
        anisotropic.u12 = try std.fmt.parseInt(i32, strings.removeSpaces(raw_line[63..70]), 10);
        if (raw_line.len > 76) {
            const element = strings.removeSpaces(raw_line[76..78]);
            if (element.len != 0) {
                anisotropic.element = try allocator.dupe(u8, element);
            }
            if (raw_line.len == 80) {
                const charge = strings.removeSpaces(raw_line[78..80]);
                if (charge.len != 0) {
                    anisotropic.charge = try allocator.dupe(u8, charge);
                }
            }
        }
        return anisotropic;
    }

    /// Frees all the strings in the struct
    pub fn free(self: *AnisotropicRecord, allocator: std.mem.Allocator) void {
        if (self.charge != null) {
            allocator.free(self.charge.?);
        }
        if (self.element != null) {
            allocator.free(self.element.?);
        }
        allocator.free(self.name);
        allocator.free(self.resName);
    }
};

/// Represents a CRYST1 record
pub const CrystalRecord = struct {
    a: f32 = undefined,
    b: f32 = undefined,
    c: f32 = undefined,
    alpha: f32 = undefined,
    beta: f32 = undefined,
    gamma: f32 = undefined,
    spaceGroup: string = undefined,
    z: u16 = undefined,

    // TODO: See if lines adhere to using all parameters
    pub fn new(raw_line: []const u8, allocator: std.mem.Allocator) !CrystalRecord {
        return .{
            .a = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[6..15])),
            .b = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[15..24])),
            .c = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[24..33])),
            .alpha = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[33..40])),
            .beta = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[40..47])),
            .gamma = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[47..54])),
            .spaceGroup = try allocator.dupe(u8, strings.removeSpaces(raw_line[55..66])),
            .z = try std.fmt.parseInt(u16, strings.removeSpaces(raw_line[66..70]), 10),
        };
    }

    pub fn free(self: *CrystalRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.spaceGroup);
    }
};

test "parse CRYST1 record" {
    const line = "CRYST1   52.000   58.600   61.900  90.00  90.00  90.00 P 21 21 21    8          ";
    var crystal = try CrystalRecord.new(line, testalloc);
    defer crystal.free(testalloc);
    try expectEqual(52.000, crystal.a);
    try expectEqual(58.600, crystal.b);
    try expectEqual(61.900, crystal.c);
    try expectEqual(90.00, crystal.alpha);
    try expectEqual(90.00, crystal.beta);
    try expectEqual(90.00, crystal.gamma);
    try testing.expectEqualStrings("P 21 21 21", crystal.spaceGroup);
    try testing.expectEqual(8, crystal.z);
}

/// Represents a MODEL record
pub const ModelRecord = struct {
    serial: u32 = undefined,

    pub fn new(raw_line: []const u8) !ModelRecord {
        return .{
            .serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[10..14]), 10),
        };
    }
};

pub const OrigxnRecord = struct {
    N: u16 = undefined,
    On1: f32 = undefined,
    On2: f32 = undefined,
    On3: f32 = undefined,
    Tn: f32 = undefined,

    pub fn new(raw_line: []const u8) !OrigxnRecord {
        return .{
            .N = @as(u16, raw_line[5]) - 48,
            .On1 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[10..20])),
            .On2 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[20..30])),
            .On3 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[30..40])),
            .Tn = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[45..55])),
        };
    }
};

test "parse ORIGXn Record" {
    const line = "ORIGX1      0.963457  0.136613  0.230424       16.61000                         ";
    const origxn = try OrigxnRecord.new(line);
    try expectEqual(1, origxn.N);
    try expectEqual(0.963457, origxn.On1);
    try expectEqual(0.136613, origxn.On2);
    try expectEqual(0.230424, origxn.On3);
    try expectEqual(16.61000, origxn.Tn);
}

/// Represents a SCALEn record
pub const ScalenRecord = struct {
    N: u16 = undefined,
    Sn1: f32 = undefined,
    Sn2: f32 = undefined,
    Sn3: f32 = undefined,
    Un: f32 = undefined,

    pub fn new(raw_line: []const u8) !ScalenRecord {
        return .{
            .N = @as(u16, raw_line[5]) - 48,
            .Sn1 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[10..20])),
            .Sn2 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[20..30])),
            .Sn3 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[30..40])),
            .Un = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[45..55])),
        };
    }
};

test "parse SCALEn record" {
    const line = "SCALE1      0.019231  0.000000  0.000000        0.00000                         ";
    const scalen = try ScalenRecord.new(line);
    try expectEqual(1, scalen.N);
    try expectEqual(0.019231, scalen.Sn1);
    try expectEqual(0.000000, scalen.Sn2);
    try expectEqual(0.000000, scalen.Sn3);
    try expectEqual(0.00000, scalen.Un);
}

// zig fmt: off
/// An enum derived of possible records in a PDB file
pub const RecordType = enum(u48) {
    atom =    std.mem.readInt(u48, "ATOM  ", .little),
    hetatm =  std.mem.readInt(u48, "HETATM", .little),
    term =    std.mem.readInt(u48, "TER   ", .little),
    connect = std.mem.readInt(u48, "CONECT", .little),
    model =   std.mem.readInt(u48, "MODEL ", .little),
    anisou = std.mem.readInt(u48, "ANISOU", .little),
    cryst1 = std.mem.readInt(u48, "CRYST1", .little),
    origx1 = std.mem.readInt(u48, "ORIGX1", .little),
    origx2 = std.mem.readInt(u48, "ORIGX2", .little),
    origx3 = std.mem.readInt(u48, "ORIGX3", .little),
    scale1 = std.mem.readInt(u48, "SCALE1", .little),
    scale2 = std.mem.readInt(u48, "SCALE2", .little),
    scale3 = std.mem.readInt(u48, "SCALE3", .little),
    endmdl = std.mem.readInt(u48, "ENDMDL", .little),
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
    /// An ANISOU record
    anisou: AnisotropicRecord,
    /// A CRYST1 record
    cryst1: CrystalRecord,
    /// origxn records
    origx1: OrigxnRecord,
    origx2: OrigxnRecord,
    origx3: OrigxnRecord,
    // scalen records
    scale1: ScalenRecord,
    scale2: ScalenRecord,
    scale3: ScalenRecord,
    /// An ENDMDL record
    endmdl: void,

    /// Parses a line into a record
    pub fn parse(
        raw_line: []const u8,
        tag: RecordType,
        index: u32,
        allocator: std.mem.Allocator,
    ) !Record {
        const record: Record = switch (tag) {
            inline .atom, .hetatm => |t| @unionInit(
                Record,
                @tagName(t),
                try AtomRecord.new(raw_line, index, allocator),
            ),
            inline .term => |t| @unionInit(
                Record,
                @tagName(t),
                try TermRecord.new(raw_line, allocator),
            ),
            inline .model => |t| @unionInit(
                Record,
                @tagName(t),
                try ModelRecord.new(raw_line),
            ),
            inline .connect => |t| @unionInit(
                Record,
                @tagName(t),
                try ConnectRecord.new(raw_line),
            ),
            inline .anisou => |t| @unionInit(
                Record,
                @tagName(t),
                try AnisotropicRecord.new(raw_line, allocator),
            ),
            inline .cryst1 => |t| @unionInit(
                Record,
                @tagName(t),
                try CrystalRecord.new(raw_line, allocator),
            ),
            inline .origx1, .origx2, .origx3 => |t| @unionInit(
                Record,
                @tagName(t),
                try OrigxnRecord.new(raw_line),
            ),
            inline .scale1, .scale2, .scale3 => |t| @unionInit(
                Record,
                @tagName(t),
                try ScalenRecord.new(raw_line),
            ),
            .endmdl => .endmdl,
        };

        return record;
    }

    /// Returns a record's chain ID if it has one
    pub fn chainID(self: Record) ?char {
        return switch (self) {
            .atom, .hetatm => |payload| payload.chainID,
            .anisou => |payload| payload.chainID,
            else => null,
        };
    }

    /// Returns a record's alternate location if it has one
    pub fn altLoc(self: Record) ?char {
        return switch (self) {
            .atom, .hetatm => |payload| payload.altLoc,
            .anisou => |payload| payload.altLoc,
            else => null,
        };
    }

    /// Returns a record's element if it has one
    pub fn name(self: Record) ?string {
        return switch (self) {
            .atom, .hetatm => |payload| payload.name,
            .anisou => |payload| payload.name,
            else => null,
        };
    }

    /// Returns a record's residue name if it has one
    pub fn resName(self: Record) ?string {
        return switch (self) {
            .atom, .hetatm => |payload| payload.resName,
            .term => |payload| payload.resName,
            .anisou => |payload| payload.resName,
            else => null,
        };
    }

    /// Returns a record's serial number
    pub fn serial(self: Record) u32 {
        return switch (self) {
            .term => |payload| payload.serial,
            .atom, .hetatm => |payload| payload.serial,
            .connect => |payload| payload.serial,
            .anisou => |payload| payload.serial,
            .model => |payload| payload.serial,
            else => 0,
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
            const uInfo = @typeInfo(@TypeOf(self)).Union;
            if (uInfo.tag_type) |UnionTagType| {
                inline for (uInfo.fields) |uField| {
                    if (self == @field(UnionTagType, uField.name)) {
                        switch (@typeInfo(uField.type)) {
                            .Void => try writer.print("{s}", .{uField.name}),
                            .Struct => {
                                const fields = @typeInfo(uField.type).Struct.fields;
                                inline for (fields) |field| {
                                    const fmt2 = switch (@typeInfo(field.type)) {
                                        .Optional => |optional| switch (@typeInfo(optional.child)) {
                                            .Pointer => |ptr_info| switch (ptr_info.size) {
                                                .Slice, .Many => "{?s}",
                                                else => "{?}",
                                            },
                                            else => "{?}",
                                        },
                                        .Float => "{d:.3}",
                                        .Int => "{}",
                                        .Pointer => |ptr_info| switch (ptr_info.size) {
                                            .Slice, .Many => "{s}",
                                            else => "{}",
                                        },
                                        // .Pointer => |ptr| if (ptr.child == .Slice) "{s}",
                                        else => "{}",
                                    };
                                    try writer.print("{s}:" ++ fmt2 ++ " ", .{ field.name, @field(@field(self, uField.name), field.name) });
                                    // try writer.print("{s}:" ++ fmt2 ++ " ", .{ field.name, @field(uField.type, field.name) });
                                }
                            },
                            else => try writer.print("{?}", .{@field(self, uField.name)}),
                        }
                    }
                }
            }
        }
    }

    /// Calls free on a record if it has any allocated memory
    pub fn free(self: *Record, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .atom, .hetatm => |*atom| atom.free(allocator),
            .term => |*ter| ter.free(allocator),
            .anisou => |*anisou| anisou.free(allocator),
            .cryst1 => |*cryst1| cryst1.free(allocator),
            .model, .connect, .origx1, .origx2, .origx3, .scale1, .scale2, .scale3, .endmdl => return,
        }
    }
};

test "Anisotropic Record" {
    const line = "ANISOU    1  N   MET A   1      688   1234    806    -19    -49    178       N  ";
    var record = try AnisotropicRecord.new(line, testalloc);
    defer record.free(testalloc);
    try expectEqual(1, record.serial);
    try testing.expectEqualStrings("N", record.name);
    try testing.expectEqualStrings("MET", record.resName);
    try expectEqual('A', record.chainID);
    try expectEqual(1, record.resSeq);
    try expectEqual(688, record.u00);
    try expectEqual(1234, record.u11);
    try expectEqual(806, record.u22);
    try expectEqual(-19, record.u01);
    try expectEqual(-49, record.u02);
    try expectEqual(178, record.u12);
    try testing.expectEqualStrings("N", record.element.?);
}

test "Connect Record" {
    const line = "CONECT  413  412  414                                                           ";
    const connectRecord = try ConnectRecord.new(line);
    try expectEqual(413, connectRecord.serial);
    try expectEqual(412, connectRecord.serial1);
    try expectEqual(414, connectRecord.serial2);
    try expectEqual(null, connectRecord.serial3);
    try expectEqual(null, connectRecord.serial4);
}

// i noticed you weren't able to see the difference between strings.  this is why
// i've used expectEqualStrings() below.  and this helper will also print out
// the expected vs actual values when they differ.
fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected, actual); // peer type resolution
    return testing.expectEqual(@as(T, expected), actual);
}

test "convert to atoms" {
    const line = "ATOM     17  NE2 GLN     2      25.562  32.733   1.806  1.00 19.49      1UBQ";
    var atom = try AtomRecord.new(line, 1, testalloc);
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
    var atom = try AtomRecord.new(line, 1, testalloc);
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
        const atom = try AtomRecord.new(line, 0, testalloc);
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
