const std = @import("std");
const strings = @import("../strings.zig");

/// Represents a MODEL record
pub const ModelRecord = struct {
    serial: u32 = undefined,

    pub fn new(raw_line: []const u8) !ModelRecord {
        return .{
            .serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[10..14]), 10),
        };
    }
};
