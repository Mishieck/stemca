//! A row in a CSV table. Its cells are `Abbreviation`, `Expansion`, and
//! `Category`.

const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;
const ascii = std.ascii;

const format_utils = @import("format");

const Self = @This();

pub const SEPARATOR_ARRAY = [1]u8{SEPARATOR};
pub const SEPARATOR = ',';
pub const DELIMITER = '\n';
pub const DELIMITER_ARRAY = [1]u8{DELIMITER};

pub const Slice = []const u8;
pub const Array = [3]Cell;
pub const Cell = []const u8;
pub const Abbreviation = []const u8;

/// A row in a CSV string. It is separated usgin `,` and delimited using `\n`.
slice: Slice,

/// Returns the abbreviation cell value. Does not guard against invalid CSV.
pub fn get_abbreviation(self: *const Self) Cell {
    return mem.sliceTo(self.slice, SEPARATOR);
}

/// Returns the expansion cell value. Does not guard against invalid CSV.
pub fn get_expansion(self: *const Self) Cell {
    const start_index = mem.indexOf(u8, self.slice, &SEPARATOR_ARRAY).? + 1;
    const end_index = mem.lastIndexOf(u8, self.slice, &SEPARATOR_ARRAY).?;
    return self.slice[start_index..end_index];
}

/// Returns the category cell value. Does not guard against invalid CSV.
pub fn get_category(self: *const Self) Cell {
    const start_index = mem.lastIndexOf(u8, self.slice, &SEPARATOR_ARRAY).? + 1;
    const end_index = mem.indexOf(u8, self.slice, &DELIMITER_ARRAY).?;
    return self.slice[start_index..end_index];
}

/// Creates a row from an array of cells. Caller owns the memory. Call
/// `Row.destroy` to free the memory.
pub fn fromArray(allocator: mem.Allocator, array: Array) !*Self {
    const joined = try mem.join(allocator, &SEPARATOR_ARRAY, &array);
    defer allocator.free(joined);
    const slice = try mem.concat(allocator, u8, &.{ joined, &DELIMITER_ARRAY });
    const self = try allocator.create(Self);
    self.* = .{ .slice = slice };
    return self;
}

pub fn destroy(self: *Self, allocator: mem.Allocator) void {
    allocator.free(self.slice);
    allocator.destroy(self);
}

/// Formats a row for displaying. Caller owns the memory.
pub fn format(self: *const Self, gpa: mem.Allocator) ![]const u8 {
    const template =
        \\Abbreviation: {s}
        \\Expansion:    {s}
        \\Category:     {s}
        \\
    ;

    return try fmt.allocPrint(gpa, template, .{
        self.get_abbreviation(),
        self.get_expansion(),
        self.get_category(),
    });
}

/// Creates a Table row with a newline at the end. Caller owns the memory.
pub fn toTableRow(
    self: *const Self,
    gpa: mem.Allocator,
    column_sizes: [3]usize,
) ![]const u8 {
    const table_row_template = "{s}{s}{s}{s}{s}\n";
    const abbreviation = self.get_abbreviation();
    const expansion = self.get_expansion();
    const category = self.get_category();

    const first_colum_padding = try format_utils.repeatString(
        gpa,
        " ",
        column_sizes[0] - abbreviation.len,
    );
    defer gpa.free(first_colum_padding);

    const second_colum_padding = try format_utils.repeatString(
        gpa,
        " ",
        column_sizes[1] - expansion.len,
    );
    defer gpa.free(second_colum_padding);

    return try fmt.allocPrint(
        gpa,
        table_row_template,
        .{
            abbreviation,
            first_colum_padding,
            expansion,
            second_colum_padding,
            category,
        },
    );
}

pub fn match(self: *const Self, abbr: Abbreviation) bool {
    const row_abbr = self.get_abbreviation();
    if (abbr.len != row_abbr.len) return false;

    return for (abbr, 0..) |char, i| {
        if (ascii.toUpper(char) != ascii.toUpper(row_abbr[i])) break false;
    } else true;
}

test "Row.fromArray" {
    const allocator = testing.allocator;
    const array = Array{ "AI", "Artificial Intelligence", "STEM" };
    var row = try Self.fromArray(allocator, array);
    defer row.destroy(allocator);

    const expected = "AI,Artificial Intelligence,STEM\n";
    try testing.expectEqualStrings(expected, row.slice);
}

test "Row Cells" {
    const allocator = testing.allocator;

    const cells = Array{ "AI", "Artificial Intelligence", "STEM" };
    var row = try Self.fromArray(allocator, cells);
    defer row.destroy(allocator);

    try testing.expectEqualStrings(cells[0], row.get_abbreviation());
    try testing.expectEqualStrings(cells[1], row.get_expansion());
    try testing.expectEqualStrings(cells[2], row.get_category());
}

test "Row.format" {
    const allocator = testing.allocator;

    const array = Array{ "AKA", "Also Known As", "Common" };
    var row = try Self.fromArray(allocator, array);
    defer row.destroy(allocator);
    const formatted = try row.format(allocator);
    defer allocator.free(formatted);

    const expected =
        \\Abbreviation: AKA
        \\Expansion:    Also Known As
        \\Category:     Common
        \\
    ;

    try std.testing.expectEqualStrings(expected, formatted);
}

test "Row.toTableRow" {
    const allocator = testing.allocator;

    const array = Array{ "AKA", "Also Known As", "Common" };
    var row = try Self.fromArray(allocator, array);
    defer row.destroy(allocator);
    const formatted = try row.toTableRow(allocator, .{ 5, 15, 7 });
    defer allocator.free(formatted);

    const expected = "AKA  Also Known As  Common\n";
    try std.testing.expectEqualStrings(expected, formatted);
}

test "Row.match" {
    const allocator = testing.allocator;

    const array = Array{ "AKA", "Also Known As", "Common" };
    var row = try Self.fromArray(allocator, array);
    defer row.destroy(allocator);

    try std.testing.expect(row.match("AKA"));
    try std.testing.expect(row.match("aKA"));
    try std.testing.expect(row.match("AkA"));
    try std.testing.expect(row.match("AKa"));
    try std.testing.expect(row.match("aka"));

    try std.testing.expect(!row.match("ak"));
    try std.testing.expect(!row.match("akak"));
}
