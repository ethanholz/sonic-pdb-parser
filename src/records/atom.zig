const std = @import("std");
const strings = @import("../strings.zig");

const testing = std.testing;
const testalloc = std.testing.allocator;
const expectEqual = @import("test_helper.zig").expectEqual;

/// Represents an ATOM or HETATM record
pub const AtomRecord = struct {
    serial: u32 = undefined,
    name: []const u8 = undefined,
    altLoc: ?u8 = null,
    resName: []const u8 = undefined,
    chainID: u8 = undefined,
    resSeq: u16 = undefined,
    iCode: ?u8 = null,
    x: f32 = undefined,
    y: f32 = undefined,
    z: f32 = undefined,
    occupancy: f32 = undefined,
    tempFactor: f32 = undefined,
    element: ?[]const u8 = null,
    charge: ?[]const u8 = null,
    entry: ?[]const u8 = null,

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
