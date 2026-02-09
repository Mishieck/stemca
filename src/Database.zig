const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;

const Self = @This();

arena: mem.Allocator,
rows: *array_list.Managed(*Row),

pub fn fromIterator(
    comptime Data: type,
    arena: mem.Allocator,
    iterator: RowIterator(Data),
) !*Self {
    const rows = try arena.create(RowList);
    rows.* = .init(arena);
    const self = try arena.create(Self);
    self.* = .{ .arena = arena, .rows = rows };
    try self.mergeIterator(Data, iterator);
    return self;
}

pub fn destroy(self: *Self) void {
    for (self.rows.items) |row| row.destroy(self.arena);
    self.arena.destroy(self.rows);
    self.arena.destroy(self);
}

pub fn mergeIterator(
    self: *Self,
    comptime Data: type,
    iterator: RowIterator(Data),
) !void {
    _ = try iterator.next(self.arena, iterator.data); // Discard the table head
    while (try iterator.next(self.arena, iterator.data)) |row| {
        try self.rows.append(row);
    }
}

// TODO: Change this to 'lookup'.
pub fn matchAbbreviation(self: *const Self, abbr: []const u8) !RowSlice {
    var list = std.ArrayList(*const Row){};
    const upper_abbr = try stringToUpperCase(self.arena, abbr);

    for (self.rows.items) |row| {
        const row_abbr = row.get_abbreviation();
        const row_upper_abbr = try stringToUpperCase(self.arena, row_abbr);
        const is_match = mem.eql(u8, upper_abbr, row_upper_abbr);
        if (is_match) try list.append(self.arena, row);
    }

    return list.items;
}

pub fn toCsvTable(self: *const Self) ![]const u8 {
    var rows = std.ArrayList(u8){};
    try rows.appendSlice(self.arena, "Abbreviation,Expansion,Category\n");

    for (self.rows.items) |row| try rows.appendSlice(
        self.arena,
        try row.toCsvRow(self.arena),
    );

    return rows.items;
}

pub fn stringToUpperCase(allocator: mem.Allocator, string: []const u8) ![]const u8 {
    var upper_abbr = try allocator.dupe(u8, string);
    for (upper_abbr, 0..) |c, i| upper_abbr[i] = std.ascii.toUpper(c);
    return upper_abbr;
}

pub const Separator = ',';
pub const RowList = array_list.Managed(*Row);
pub const RowSlice = []*const Row;

pub const ListRowIterator = struct {
    pub const Iterator = RowIterator(Data);

    pub const Data = struct {
        const List = []const []const u8;
        list: List,
        index: *usize,
    };

    pub fn init(allocator: mem.Allocator, list: Data.List) Iterator {
        const index = allocator.create(usize) catch unreachable;
        index.* = 0;

        return .{
            .data = .{ .list = list, .index = index },
            .next = nextListRow,
        };
    }

    pub fn nextListRow(allocator: mem.Allocator, data: Data) anyerror!?*Row {
        if (data.list.len == 0 or data.index.* == data.list.len) return null;
        const row = try Row.fromString(allocator, data.list[data.index.*]);
        data.index.* += 1;
        return row;
    }
};

pub fn RowIterator(comptime Data: type) type {
    return struct {
        data: Data,
        next: *const fn (allocator: mem.Allocator, data: Data) anyerror!?*Row,
    };
}

pub const Row = struct {
    pub const Array = array_list.Managed(Cell);
    pub const Cell = []const u8;

    array: *Array,

    pub fn fromArray(allocator: mem.Allocator, array: Array) !*Row {
        const owned_array = try allocator.create(Array);
        owned_array.* = array;
        const self = try allocator.create(Row);
        self.* = .{ .array = owned_array };
        return self;
    }

    pub fn fromString(arena: mem.Allocator, string: []const u8) !*Row {
        var cell_iterator = mem.splitScalar(u8, string, Separator);
        var array = Array.init(arena);

        var i: usize = 0;
        while (cell_iterator.next()) |cell| : (i += 1) {
            const copy = try arena.dupe(u8, mem.trim(u8, cell, " "));
            try array.append(copy);
        }

        return try fromArray(arena, array);
    }

    pub fn destroy(self: *Row, allocator: mem.Allocator) void {
        self.array.clearAndFree();
        allocator.destroy(self.array);
        allocator.destroy(self);
    }

    pub fn get_abbreviation(self: *const Row) Cell {
        return self.array.items[0];
    }

    pub fn get_expansion(self: *const Row) Cell {
        return self.array.items[1];
    }

    pub fn get_category(self: *const Row) Cell {
        return self.array.items[2];
    }

    /// Formats a row for displaying. Caller owns the memory.
    pub fn format(self: *const Row, gpa: mem.Allocator) ![]const u8 {
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

    /// Creates a CSV row with a newline at the end. Caller owns the memory.
    pub fn toCsvRow(self: *const Row, gpa: mem.Allocator) ![]const u8 {
        const string = try mem.join(gpa, ",", self.array.items);
        defer gpa.free(string);
        return try mem.concat(gpa, u8, &.{ string, "\n" });
    }

    /// Creates a Table row with a newline at the end. Caller owns the memory.
    pub fn toTableRow(
        self: *const Row,
        gpa: mem.Allocator,
        column_sizes: [3]usize,
    ) ![]const u8 {
        const table_row_template = "{s}{s}{s}{s}{s}\n";
        const cells = self.array.items;

        const first_colum_padding = try repeatString(
            gpa,
            " ",
            column_sizes[0] - cells[0].len,
        );
        defer gpa.free(first_colum_padding);

        const second_colum_padding = try repeatString(
            gpa,
            " ",
            column_sizes[1] - cells[1].len,
        );
        defer gpa.free(second_colum_padding);

        return try fmt.allocPrint(
            gpa,
            table_row_template,
            .{
                cells[0],
                first_colum_padding,
                cells[1],
                second_colum_padding,
                cells[2],
            },
        );
    }
};

pub fn repeatString(
    allocator: std.mem.Allocator,
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
    try std.testing.expectEqualStrings("abcabcabc", repeated);
}

test "Database.fromIterator" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const iterator = ListRowIterator.init(allocator, &.{
        "Abbreviation,Expansion,Category",
        "AI,Artificial Intelligence,STEM",
        "AKA,Also Known As,Common",
    });

    var db = try fromIterator(ListRowIterator.Data, allocator, iterator);
    errdefer db.destroy();
    var row = db.rows.items[0];

    try testing.expectEqualStrings("AI", row.get_abbreviation());
    try testing.expectEqualStrings("Artificial Intelligence", row.get_expansion());
    try testing.expectEqualStrings("STEM", row.get_category());

    row = db.rows.getLast();
    try testing.expectEqualStrings("AKA", row.get_abbreviation());

    db.destroy();
}

test "Database.mergeIterator" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const common_list = [_][]const u8{
        "Abbreviation,Expansion,Category",
        "AKA,Also Known As,Common",
        "RSVP,Please Respond,Common",
    };

    const stem_list = [_][]const u8{
        "Abbreviation,Expansion,Category",
        "AI,Artificial Intelligence,STEM",
        "CAD,Computer-Aided Design,STEM",
    };

    const common_iterator = ListRowIterator.init(allocator, &common_list);
    const stem_iterator = ListRowIterator.init(allocator, &stem_list);

    var db = try fromIterator(ListRowIterator.Data, allocator, common_iterator);
    errdefer db.destroy();

    try db.mergeIterator(ListRowIterator.Data, stem_iterator);

    const abbreviations = [_][]const u8{ "AKA", "RSVP", "AI", "CAD" };

    try testing.expectEqual(4, db.rows.items.len);

    for (abbreviations) |abbr| {
        const rows = try db.matchAbbreviation(abbr);
        try testing.expectEqual(1, rows.len);
    }

    db.destroy();
}

test "Database.matchAbbreviation" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const iterator = ListRowIterator.init(allocator, &.{
        "Abbreviation,Expansion,Category",
        "AI,Artificial Intelligence,STEM",
        "AKA,Also Known As,Common",
        "IoT,Internet of Things,STEM",
        "STD,Standard,STEM",
        "STD,Sexually Transmitted Disease,Common",
    });

    var db = try fromIterator(ListRowIterator.Data, allocator, iterator);
    errdefer db.destroy();

    const ai_expansion = "Artificial Intelligence";
    const iot_expansion = "Internet of Things";

    // Exact Match
    try testMatchAbbreviation(db, "AI", &.{ai_expansion});

    // Input Not Uppercase
    try testMatchAbbreviation(db, "ai", &.{ai_expansion});

    // Database Abbreviation Not Uppercase
    try testMatchAbbreviation(db, "IoT", &.{iot_expansion});

    // Input and Database Abbreviation Not Uppercase
    try testMatchAbbreviation(db, "iot", &.{iot_expansion});

    // Multiple Matches
    const std_expansions = &.{ "Standard", "Sexually Transmitted Disease" };
    try testMatchAbbreviation(db, "STD", std_expansions);

    db.destroy();
}

fn testMatchAbbreviation(
    db: *const Self,
    abbr: []const u8,
    matches: []const []const u8,
) !void {
    const rows = try db.matchAbbreviation(abbr);
    try testing.expectEqual(matches.len, rows.len);

    for (matches, 0..) |m, i| {
        try testing.expectEqualStrings(m, rows[i].get_expansion());
    }
}

test "Row.fromString" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const string = "AKA,Also Known As,Common";
    var row = try Row.fromString(allocator, string);
    defer row.destroy(allocator);

    try testing.expectEqualStrings("AKA", row.get_abbreviation());
    try testing.expectEqualStrings("Also Known As", row.get_expansion());
    try testing.expectEqualStrings("Common", row.get_category());
}

test "Row.fromArray" {
    const allocator = testing.allocator;

    var array = Row.Array.init(allocator);
    try array.appendSlice(&.{ "AKA", "Also Known As", "Common" });
    var row = try Row.fromArray(allocator, array);
    defer row.destroy(allocator);

    try testing.expectEqualStrings(row.array.items[0], row.get_abbreviation());
    try testing.expectEqualStrings(row.array.items[1], row.get_expansion());
    try testing.expectEqualStrings(row.array.items[2], row.get_category());
}

test "Row.format" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var array = Row.Array.init(allocator);
    try array.appendSlice(&.{ "AKA", "Also Known As", "Common" });
    var row = try Row.fromArray(allocator, array);
    defer row.destroy(allocator);

    const formatted = try row.format(allocator);

    const expected =
        \\Abbreviation: AKA
        \\Expansion:    Also Known As
        \\Category:     Common
        \\
    ;

    try std.testing.expectEqualStrings(expected, formatted);
}

test "Row.toCsvRow" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var array = Row.Array.init(allocator);
    try array.appendSlice(&.{ "AKA", "Also Known As", "Common" });
    var row = try Row.fromArray(allocator, array);
    defer row.destroy(allocator);

    const csv_row = try row.toCsvRow(allocator);
    try std.testing.expectEqualStrings("AKA,Also Known As,Common\n", csv_row);
}

test "Row.toTableRow" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var array = Row.Array.init(allocator);
    try array.appendSlice(&.{ "AKA", "Also Known As", "Common" });
    var row = try Row.fromArray(allocator, array);
    defer row.destroy(allocator);

    const table_row = try row.toTableRow(allocator, .{ 5, 15, 7 });

    try std.testing.expectEqualStrings(
        "AKA  Also Known As  Common\n",
        table_row,
    );
}
