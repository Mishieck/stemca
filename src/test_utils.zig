const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const fs = std.fs;

pub const Table = []const [3][]const u8;

pub const TABLE = [_][3][]const u8{
    .{ "Abbreviation", "Expansion", "Category" },
    .{ "AI", "Artificial Intelligence", "STEM" },
    .{ "AKA", "Also Known As", "Common" },
    .{ "CAD", "Computer-Aided Design", "STEM" },
    .{ "IoT", "Internet of Things", "STEM" },
    .{ "RSVP", "Please Respond", "Common" },
    .{ "TL;DR", "Too Long; Didn't Read", "Common" },
};

pub const TABLE_2 = [_][3][]const u8{
    .{ "Abbreviation", "Expansion", "Category" },
    .{ "MRI", "Magnetic Resonance Imaging", "STEM" },
    .{ "NASA", "National Aeronautics and Space Administration", "STEM" },
    .{ "OOO", "Out of Office", "Common" },
    .{ "RAM", "Random Access Memory", "STEM" },
    .{ "ROI", "Return on Investment", "Common" },
    .{ "TBD", "To Be Determined", "Common" },
    .{ "TBH", "To Be Honest", "Common" },
};

/// Creates a file in `dir` with default name and content.
pub fn createDefaultFile(allocator: mem.Allocator, dir: fs.Dir) !fs.File {
    var table_text = try createDefaultTableText(allocator);
    defer table_text.clearAndFree(allocator);
    const filename = "data.csv";
    return try createFile(dir, filename, table_text.items);
}

/// Creates a file in a `dir`ectory. It writes the `data` to the file.
pub fn createFile(dir: fs.Dir, path: []const u8, data: []const u8) !fs.File {
    try dir.writeFile(.{
        .data = data,
        .sub_path = path,
    });

    return try dir.openFile(path, .{ .mode = .read_write });
}

pub fn createDefaultTableText(allocator: mem.Allocator) !std.ArrayList(u8) {
    return createTableText(allocator, &TABLE);
}

pub fn createTableText(
    allocator: mem.Allocator,
    slice: []const [3][]const u8,
) !std.ArrayList(u8) {
    var table_text = std.ArrayList(u8){};

    for (slice) |row| {
        const r = try mem.join(allocator, ",", &row);
        defer allocator.free(r);
        const line = try mem.concat(allocator, u8, &.{ r, "\n" });
        defer allocator.free(line);
        try table_text.appendSlice(allocator, line);
    }

    return table_text;
}
