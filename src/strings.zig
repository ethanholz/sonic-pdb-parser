const std = @import("std");
pub fn equals(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn removeSpaces(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}

test "removeSpaces" {
    try std.testing.expectEqualStrings("ATOM", removeSpaces("ATOM  "));
    try std.testing.expectEqualStrings("", removeSpaces("     "));
}
