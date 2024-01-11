const std = @import("std");
const testing = std.testing;

pub fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected, actual); // peer type resolution
    return testing.expectEqual(@as(T, expected), actual);
}
