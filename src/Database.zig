const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;

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
    _ = try iterator.next(arena, iterator.data); // Discard the headings
    while (try iterator.next(arena, iterator.data)) |row| try rows.append(row);
    const self = try arena.create(Self);
    self.* = .{ .arena = arena, .rows = rows };
    return self;
}

pub fn destroy(self: *Self) void {
    for (self.rows.items) |row| row.destroy(self.arena);
    self.arena.destroy(self.rows);
    self.arena.destroy(self);
}

pub const Separator = ',';
pub const RowList = array_list.Managed(*Row);

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
};

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
