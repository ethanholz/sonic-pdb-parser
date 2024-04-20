const std = @import("std");
const strings = @import("strings");

const expectEqual = @import("test_helper.zig").expectEqual;
const testing = std.testing;
const testalloc = testing.allocator;

/// Represents a CRYST1 record
pub const CrystalRecord = struct {
    a: f32 = undefined,
    b: f32 = undefined,
    c: f32 = undefined,
    alpha: f32 = undefined,
    beta: f32 = undefined,
    gamma: f32 = undefined,
    spaceGroup: []const u8 = undefined,
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
