const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;

const Database = @import("./Database.zig");
const RowIterator = Database.RowIterator;

pub const FileRowIterator = RowIterator(*FileRowIteratorData);

pub const FileRowIteratorData = struct {
    file: *fs.File,
    reader: *fs.File.Reader,
    buffer: *[1024]u8,
};

pub fn createFileRowIterator(
    arena: mem.Allocator,
    dir: fs.Dir,
    file_path: []const u8,
) !FileRowIterator {
    const file = try arena.create(fs.File);
    file.* = try dir.openFile(file_path, .{ .mode = .read_only });
    const buffer = try arena.create([1024]u8);
    buffer.* = undefined;
    const reader = try arena.create(fs.File.Reader);
    reader.* = file.reader(&buffer.*);

    const data = try arena.create(FileRowIteratorData);

    data.* = .{
        .file = file,
        .reader = reader,
        .buffer = buffer,
    };

    return FileRowIterator{
        .data = data,
        .next = getNextLine,
    };
}

pub fn getNextLine(arena: mem.Allocator, data: *FileRowIteratorData) anyerror!?*Database.Row {
    var alloc_writer = std.Io.Writer.Allocating.init(arena);
    defer alloc_writer.deinit();
    const written = try data.reader.interface.takeDelimiterExclusive('\n');
    var row: ?*Database.Row = null;
    row = try Database.Row.fromString(arena, written);
    return row;
}

test createFileRowIterator {
    const gpa_allocator = testing.allocator;
    var arena = heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const table = [_][3][]const u8{
        .{ "Abbreviation", "Expansion", "Category" },
        .{ "AI", "Artificial Intelligence", "STEM" },
        .{ "AKA", "Also Known As", "Common" },
        .{ "CAD", "Computer-Aided Design", "STEM" },
        .{ "IoT", "Internet of Things", "STEM" },
        .{ "RSVP", "Please Respond", "Common" },
        .{ "TL;DR", "Too Long; Didn't Read", "Common" },
    };

    var table_text = std.ArrayList(u8){};
    defer table_text.deinit(gpa_allocator);
    for (table) |row| {
        const r = try mem.join(gpa_allocator, ",", &row);
        defer gpa_allocator.free(r);
        const line = try mem.concat(gpa_allocator, u8, &.{ r, "\n" });
        defer gpa_allocator.free(line);
        try table_text.appendSlice(gpa_allocator, line);
    }

    var tmp_dir = std.testing.tmpDir(.{});
    errdefer tmp_dir.cleanup();

    const test_file = try tmp_dir.dir.createFile("test.csv", .{});
    try test_file.writeAll(table_text.items);
    errdefer test_file.close();

    const file = try tmp_dir.dir.openFile("test.csv", .{});
    defer file.close();

    var iterator = try createFileRowIterator(gpa_allocator, tmp_dir.dir, "test.csv");

    defer {
        iterator.data.file.close();
        gpa_allocator.destroy(iterator.data.file);
        gpa_allocator.destroy(iterator.data.buffer);
        gpa_allocator.destroy(iterator.data.reader);
        gpa_allocator.destroy(iterator.data);
    }

    for (table) |expected| {
        const row = try iterator.next(arena_allocator, iterator.data);
        errdefer if (row) |r| r.destroy(arena_allocator);

        try testing.expect(row != null);

        if (row) |r| {
            try testing.expectEqualStrings(expected[0], r.get_abbreviation());
            try testing.expectEqualStrings(expected[1], r.get_expansion());
            try testing.expectEqualStrings(expected[2], r.get_category());
            r.destroy(arena_allocator);
        }
    }

    tmp_dir.cleanup();
    test_file.close();
}
