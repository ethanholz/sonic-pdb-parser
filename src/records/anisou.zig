const std = @import("std");
const strings = @import("strings");

const testing = std.testing;
const testalloc = testing.allocator;
const expectEqual = @import("test_helper.zig").expectEqual;

pub const AnisotropicRecord = struct {
    serial: u32 = undefined,
    name: []const u8 = undefined,
    altLoc: ?u8 = null,
    resName: []const u8 = undefined,
    chainID: u8 = undefined,
    resSeq: u16 = undefined,
    iCode: ?u8 = null,
    u00: i32 = undefined,
    u11: i32 = undefined,
    u22: i32 = undefined,
    u01: i32 = undefined,
    u02: i32 = undefined,
    u12: i32 = undefined,
    element: ?[]const u8 = null,
    charge: ?[]const u8 = null,

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
