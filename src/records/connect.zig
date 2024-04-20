const std = @import("std");
const strings = @import("strings");

const expectEqual = @import("test_helper.zig").expectEqual;
/// Represents a CONECT record
pub const ConnectRecord = struct {
    serial: u32 = undefined,
    serial1: u32 = undefined,
    serial2: ?u32 = null,
    serial3: ?u32 = null,
    serial4: ?u32 = null,

    pub fn new(raw_line: []const u8) !ConnectRecord {
        var connect: ConnectRecord = ConnectRecord{};
        connect.serial = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[6..11]), 10);
        connect.serial1 = try std.fmt.parseInt(u32, strings.removeSpaces(raw_line[11..16]), 10);
        if (raw_line.len > 21) {
            connect.serial2 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[16..21]), 10) catch null;
        }
        if (raw_line.len > 26) {
            connect.serial3 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[21..26]), 10) catch null;
        }
        if (raw_line.len > 31) {
            connect.serial4 = std.fmt.parseInt(u32, strings.removeSpaces(raw_line[26..31]), 10) catch null;
        }
        return connect;
    }
};

test "Connect Record" {
    const line = "CONECT  413  412  414                                                           ";
    const connectRecord = try ConnectRecord.new(line);
    try expectEqual(413, connectRecord.serial);
    try expectEqual(412, connectRecord.serial1);
    try expectEqual(414, connectRecord.serial2);
    try expectEqual(null, connectRecord.serial3);
    try expectEqual(null, connectRecord.serial4);
}
