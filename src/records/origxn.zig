const std = @import("std");
const strings = @import("../strings.zig");

const expectEqual = @import("test_helper.zig").expectEqual;

pub const OrigxnRecord = struct {
    n: u16 = undefined,
    on1: f32 = undefined,
    on2: f32 = undefined,
    on3: f32 = undefined,
    tn: f32 = undefined,

    pub fn new(raw_line: []const u8) !OrigxnRecord {
        return .{
            .n = @as(u16, raw_line[5]) - 48,
            .on1 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[10..20])),
            .on2 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[20..30])),
            .on3 = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[30..40])),
            .tn = try std.fmt.parseFloat(f32, strings.removeSpaces(raw_line[45..55])),
        };
    }
};

test "parse ORIGXn Record" {
    const line = "ORIGX1      0.963457  0.136613  0.230424       16.61000                         ";
    const origxn = try OrigxnRecord.new(line);
    try expectEqual(1, origxn.n);
    try expectEqual(0.963457, origxn.on1);
    try expectEqual(0.136613, origxn.on2);
    try expectEqual(0.230424, origxn.on3);
    try expectEqual(16.61000, origxn.tn);
}
