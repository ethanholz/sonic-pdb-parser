const std = @import("std");
const strings = @import("../strings.zig");

const expectEqual = @import("test_helper.zig").expectEqual;

/// Represents a SCALEn record
pub const ScalenRecord = struct {
    n: u16 = undefined,
    sn1: f32 = undefined,
    sn2: f32 = undefined,
    sn3: f32 = undefined,
    un: f32 = undefined,

    pub fn new(raw_line: []const u8) !ScalenRecord {
        return .{
            .n = @as(u16, raw_line[5]) - 48,
            .sn1 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[10..20])),
            .sn2 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[20..30])),
            .sn3 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[30..40])),
            .un = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[45..55])),
        };
    }
};

test "parse SCALEn record" {
    const line = "SCALE1      0.019231  0.000000  0.000000        0.00000                         ";
    const scalen = try ScalenRecord.new(line);
    try expectEqual(1, scalen.n);
    try expectEqual(0.019231, scalen.sn1);
    try expectEqual(0.000000, scalen.sn2);
    try expectEqual(0.000000, scalen.sn3);
    try expectEqual(0.00000, scalen.un);
}
