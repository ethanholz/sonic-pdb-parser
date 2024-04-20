const std = @import("std");
const strings = @import("strings");

/// Represents a TER record
pub const TermRecord = struct {
    serial: u32,
    resName: []const u8,
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
