const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const fs = std.fs;

pub const Row = @import("Row.zig");
const test_utils = @import("test_utils");

const Self = @This();

pub const Buffer = [1024]u8;

gpa: mem.Allocator,
reader: *fs.File.Reader,

pub fn init(gpa: mem.Allocator, reader: *fs.File.Reader) Self {
    return .{ .gpa = gpa, .reader = reader };
}

/// Generates a row from a CSV file. Caller owns the memory. Free memory
/// using `Row.destroy`.
pub fn next(self: *Self) !?*Row {
    const read = self.reader.interface.takeDelimiterInclusive(Row.DELIMITER);
    const slice = try self.gpa.dupe(u8, read catch return null);
    const row = try self.gpa.create(Row);
    row.* = .{ .slice = slice };
    return row;
}

pub fn validateFileRowIterator(iterator: *Self) !void {
    for (test_utils.TABLE) |expected| {
        const row = try iterator.next();
        errdefer if (row) |r| r.destroy(iterator.gpa);

        try testing.expect(row != null);

        if (row) |r| {
            try testing.expectEqualStrings(expected[0], r.get_abbreviation());
            try testing.expectEqualStrings(expected[1], r.get_expansion());
            try testing.expectEqualStrings(expected[2], r.get_category());
            r.destroy(iterator.gpa);
        }
    }
}

test Self {
    const allocator = testing.allocator;

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var test_file = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer test_file.close();
    var buffer: Buffer = undefined;
    var reader = test_file.reader(&buffer);
    var iterator = Self.init(allocator, &reader);
    try validateFileRowIterator(&iterator);
    temp_dir.cleanup();
    test_file.close();
}
