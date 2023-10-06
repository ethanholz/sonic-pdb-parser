const std = @import("std");
pub fn equals(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a, b) |aItem, bItem| {
        if (bItem != aItem) {
            return false;
        }
    }
    return true;
}
pub fn removeSpaces(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}

pub fn removeSpacesAlloc(s: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const trimmed = std.mem.trim(u8, s, " ");
    const record = try allocator.alloc(u8, trimmed.len);
    @memcpy(record, trimmed);
    return record;
}

test "removeSpaces" {
    const s = [_]u8{ 'A', 'T', 'O', 'M', ' ', ' ' };
    const expected: []const u8 = "ATOM";
    const actual = removeSpaces(&s);
    try std.testing.expect(equals(expected, actual));
}
