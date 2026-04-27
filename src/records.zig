const std = @import("std");
const testing = std.testing;
const testalloc = testing.allocator;

const expectEqual = @import("records/test_helper.zig").expectEqual;
const anisou = @import("records/anisou.zig");
const atom = @import("records/atom.zig");
const connect = @import("records/connect.zig");
const crystal = @import("records/crystal.zig");
const model = @import("records/model.zig");
const origxn = @import("records/origxn.zig");
const scalen = @import("records/scalen.zig");
const term = @import("records/term.zig");

pub const recordsTypes = struct {
    pub const AnisotropicRecord = anisou.AnisotropicRecord;
    pub const AtomRecord = atom.AtomRecord;
    pub const ConnectRecord = connect.ConnectRecord;
    pub const CrystalRecord = crystal.CrystalRecord;
    pub const ModelRecord = model.ModelRecord;
    pub const OrigxnRecord = origxn.OrigxnRecord;
    pub const ScalenRecord = scalen.ScalenRecord;
    pub const TermRecord = term.TermRecord;
};

pub const AnisotropicRecord = recordsTypes.AnisotropicRecord;
pub const AtomRecord = recordsTypes.AtomRecord;
pub const ConnectRecord = recordsTypes.ConnectRecord;
pub const CrystalRecord = recordsTypes.CrystalRecord;
pub const ModelRecord = recordsTypes.ModelRecord;
pub const OrigxnRecord = recordsTypes.OrigxnRecord;
pub const ScalenRecord = recordsTypes.ScalenRecord;
pub const TermRecord = recordsTypes.TermRecord;

test {
    _ = @import("records/anisou.zig");
    _ = @import("records/atom.zig");
    _ = @import("records/anisou.zig");
    _ = @import("records/atom.zig");
    _ = @import("records/connect.zig");
    _ = @import("records/crystal.zig");
    _ = @import("records/model.zig");
    _ = @import("records/origxn.zig");
    _ = @import("records/scalen.zig");
    _ = @import("records/term.zig");
}

const string = []const u8;
const char = u8;

pub const PDB = struct {
    records: std.ArrayList(Record) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !PDB {
        var pdb = PDB{};
        pdb.records = .empty;
        pdb.allocator = allocator;
        return pdb;
    }

    pub fn deinit(self: *PDB) void {
        for (self.records.items) |*record| record.free(self.allocator);
        self.records.deinit(self.allocator);
    }

    pub fn read(self: *PDB, reader: anytype) !void {
        var recordNumber: u32 = 0;
        const end = std.mem.readInt(u48, "END   ", .little);
        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
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
            try self.records.append(self.allocator, record);
        }
    }

    pub fn format(self: PDB, writer: *std.Io.Writer) !void {
        for (self.records.items) |record| {
            try writer.print("{f}\n", .{record});
        }
    }

    pub fn writeJson(self: PDB, writer: *std.Io.Writer) !void {
        for (self.records.items) |record| {
            try record.writeJson(writer);
            try writer.writeByte('\n');
        }
    }
};

/// Reads in a PDB file and converts them to an ArrayList of records
pub fn PDBReader(reader: anytype, allocator: std.mem.Allocator) !std.ArrayList(Record) {
    var records: std.ArrayList(Record) = .empty;
    var recordNumber: u32 = 0;
    // PDB lines are should not be more than 80 characters long
    // Some of the CHARMM files are longer
    const end = std.mem.readInt(u48, "END   ", .little);
    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
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
        try records.append(allocator, record);
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
        var buffer: [1024]u8 = undefined;
        var file_writer = file.writerStreaming(&buffer);
        try file_writer.interface.print("{d},{d},{s}\n", .{ self.run, self.time, self.file });
        try file_writer.interface.flush();
    }

    pub fn writeCSVHeader(file: std.fs.File) !void {
        // const fields = @typeInfo(RunRecord).Struct.fields;
        const fields = @typeInfo(RunRecord).@"struct".fields;
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

    /// This formatter allows for printing a record from any print() method using {f}.
    pub fn format(self: Record, writer: *std.Io.Writer) !void {
        // const uInfo = @typeInfo(@TypeOf(self)).Union;
        const uInfo = @typeInfo(@TypeOf(self)).@"union";

        if (uInfo.tag_type) |UnionTagType| {
            inline for (uInfo.fields) |uField| {
                if (self == @field(UnionTagType, uField.name)) {
                    switch (@typeInfo(uField.type)) {
                        .void => try writer.print("{s}", .{uField.name}),
                        .@"struct" => {
                            const fields = @typeInfo(uField.type).@"struct".fields;
                            inline for (fields) |field| {
                                const fmt2 = switch (@typeInfo(field.type)) {
                                    .optional => |optional| switch (@typeInfo(optional.child)) {
                                        .pointer => |ptr_info| switch (ptr_info.size) {
                                            .slice, .many => "{?s}",
                                            else => "{?}",
                                        },
                                        else => "{?}",
                                    },
                                    .float => "{d:.3}",
                                    .int => "{}",
                                    .pointer => |ptr_info| switch (ptr_info.size) {
                                        .slice, .many => "{s}",
                                        else => "{}",
                                    },
                                    // .Pointer => |ptr| if (ptr.child == .Slice) "{s}",
                                    else => "{}",
                                };
                                try writer.print("{s}:" ++ fmt2 ++ " ", .{ field.name, @field(@field(self, uField.name), field.name) });
                                // try writer.print("{s}:" ++ fmt2 ++ " ", .{ field.name, @field(uField.type, field.name) });
                            }
                        },
                        else => try writer.print("{any}", .{@field(self, uField.name)}),
                    }
                }
            }
        }
    }

    pub fn writeJson(self: Record, writer: *std.Io.Writer) !void {
        try std.json.Stringify.value(self, .{}, writer);
    }

    /// Calls free on a record if it has any allocated memory
    pub fn free(self: *Record, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .atom, .hetatm => |*atom_record| atom_record.free(allocator),
            .term => |*ter| ter.free(allocator),
            .anisou => |*anisou_record| anisou_record.free(allocator),
            .cryst1 => |*cryst1| cryst1.free(allocator),
            .model, .connect, .origx1, .origx2, .origx3, .scale1, .scale2, .scale3, .endmdl => return,
        }
    }
};

// TODO: Update test to handle different lines, rather than the same
test "convert to atoms multi-line" {
    const lines = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA\nATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var atoms: std.ArrayList(AtomRecord) = .empty;
    defer {
        for (atoms.items) |*atom_record| atom_record.free(testalloc);
        atoms.deinit(testing.allocator);
    }

    var split = std.mem.splitSequence(u8, lines, "\n");
    while (split.next()) |line| {
        const atom_record = try AtomRecord.new(line, 0, testalloc);
        try atoms.append(testalloc, atom_record);
    }
    try expectEqual(2, atoms.items.len);
    for (atoms.items) |atom_record| {
        try expectEqual(1, atom_record.serial);
        try testing.expectEqualStrings("N", atom_record.name);
        try testing.expectEqualStrings("MET", atom_record.resName);
        try expectEqual(null, atom_record.iCode);
        try expectEqual(1, atom_record.resSeq);
        try expectEqual(34.774, atom_record.x);
        try expectEqual(28.332, atom_record.y);
        try expectEqual(51.752, atom_record.z);
        try expectEqual(1.00, atom_record.occupancy);
        try expectEqual(0.00, atom_record.tempFactor);
        try expectEqual(null, atom_record.element);
        try expectEqual(null, atom_record.charge);
        try testing.expectEqualStrings("PROA", atom_record.entry.?);
    }
}

test "toJson" {
    const line = "ATOM      1  N   MET     1      34.774  28.332  51.752  1.00  0.00      PROA";
    var record = try Record.parse(line, .atom, 0, testalloc);
    defer record.free(testalloc);

    // use a format specifier to print json. yet another way to avoid allocting :^)
    std.debug.print("\n{f}\n", .{std.json.fmt(record, .{})});
}
