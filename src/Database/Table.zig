const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const fs = std.fs;

pub const Row = @import("Table/Row.zig");
pub const RowIterator = @import("Table/RowIterator.zig");

const test_utils = @import("test_utils");

const Self = @This();

pub const Body = []const u8;
pub const Slice = []const u8;
pub const LookupMatches = std.ArrayList(*Row);

gpa: mem.Allocator,
buffer: *RowIterator.Buffer,
file: *fs.File,
reader: *fs.File.Reader,

/// Creates a table of abbreviations from a CSV file. Caller owns memory. Free
/// memory using `Table.destroy`.
pub fn create(gpa: mem.Allocator, file: *fs.File) !Self {
    const buffer = try gpa.create(RowIterator.Buffer);
    buffer.* = undefined;
    const reader = try gpa.create(fs.File.Reader);
    reader.* = file.reader(&buffer.*);
    return .{ .gpa = gpa, .file = file, .reader = reader, .buffer = buffer };
}

pub fn destroy(self: *Self) void {
    self.gpa.destroy(self.buffer);
    self.gpa.destroy(self.reader);
}

/// Creates `Row`s of a CSV table.
pub fn iterate(self: *const Self) !RowIterator {
    self.reader.* = self.file.reader(&self.buffer.*);
    return RowIterator.init(self.gpa, self.reader);
}

/// Looks up an abbreviation for matches. Caller owns the memory. Call
/// `ArrayList.clearAndFree` on the list and `Row.destroy` on each row.
pub fn lookup(self: *Self, abbr: Row.Abbreviation) !LookupMatches {
    var matches = std.ArrayList(*Row){};
    var iterator = try self.iterate();

    // Discard head
    const head = try iterator.next();
    defer if (head) |h| h.destroy(self.gpa);

    while (try iterator.next()) |row| {
        if (row.match(abbr)) {
            try matches.append(self.gpa, row);
        } else row.destroy(self.gpa);
    }

    return matches;
}

test iterate {
    const allocator = testing.allocator;

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var file = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer file.close();

    var table = try Self.create(allocator, &file);
    defer table.destroy();
    var iterator = try table.iterate();
    try RowIterator.validateFileRowIterator(&iterator);

    temp_dir.cleanup();
    file.close();
}

test lookup {
    const allocator = testing.allocator;

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var file = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer file.close();

    var table = try Self.create(allocator, &file);
    errdefer table.destroy();

    var matches = try table.lookup("ai");
    defer matches.clearAndFree(allocator);
    defer for (matches.items) |row| row.destroy(allocator);

    try testing.expectEqual(1, matches.items.len);

    const row = matches.items[0];
    try testing.expectEqualStrings("AI", row.get_abbreviation());

    temp_dir.cleanup();
    file.close();
    table.destroy();
}
