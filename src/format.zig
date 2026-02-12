const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

pub fn repeatString(
    allocator: mem.Allocator,
    original: []const u8,
    times: usize,
) ![]u8 {
    const total_len = original.len * times;
    const result = try allocator.alloc(u8, total_len);
    var offset: usize = 0;

    var i: usize = 0;
    while (i < times) : (i += 1) {
        @memcpy(result[offset .. offset + original.len], original);
        offset += original.len;
    }

    return result;
}

test repeatString {
    const allocator = testing.allocator;
    const repeated = try repeatString(allocator, "abc", 3);
    defer allocator.free(repeated);
    try testing.expectEqualStrings("abcabcabc", repeated);
}

/// Converts the case of a string to uppercase. Caller owns the memory.
pub fn stringToUpperCase(
    allocator: mem.Allocator,
    string: []const u8,
) ![]const u8 {
    var upper_abbr = try allocator.dupe(u8, string);
    for (upper_abbr, 0..) |c, i| upper_abbr[i] = std.ascii.toUpper(c);
    return upper_abbr;
}

test stringToUpperCase {
    const allocator = testing.allocator;
    const upper_cased = try stringToUpperCase(allocator, "abc");
    defer allocator.free(upper_cased);
    try testing.expectEqualStrings("ABC", upper_cased);
}

pub fn pluralize(
    gpa: mem.Allocator,
    string: []const u8,
    suffix: []const u8,
    item_count: usize,
) ![]const u8 {
    return try fmt.allocPrint(
        gpa,
        "{s}{s}",
        .{ string, if (item_count > 1) suffix else "" },
    );
}

test pluralize {
    const allocator = testing.allocator;

    const map = [_]struct { []const u8, []const u8, usize, []const u8 }{
        .{ "table", "s", 2, "tables" },
        .{ "table", "s", 1, "table" },
        .{ "table", "s", 0, "table" },
    };

    for (map) |entry| {
        const string, const suffix, const count, const expected = entry;
        const plural = try pluralize(allocator, string, suffix, count);
        try testing.expectEqualStrings(expected, plural);
        defer allocator.free(plural);
    }
}
