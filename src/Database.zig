const std = @import("std");
const mem = std.mem;
const array_list = std.array_list;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;
const fmt = std.fmt;

const test_utils = @import("test_utils");

pub const Table = @import("Database/Table.zig");

const Self = @This();

pub const TableList = array_list.Managed(*Table);

gpa: mem.Allocator,
tables: *TableList,

pub fn create(gpa: mem.Allocator) !Self {
    const tables = try gpa.create(TableList);
    tables.* = .init(gpa);
    return .{ .gpa = gpa, .tables = tables };
}

pub fn destroy(self: *Self) void {
    self.tables.clearAndFree();
    self.gpa.destroy(self.tables);
}

/// Looks up an abbreviation for matches. Caller owns the memory. Call
/// `ArrayList.clearAndFree` on the list and `Row.destroy` on each row.
pub fn lookup(self: *const Self, abbr: []const u8) !Table.LookupMatches {
    var list = Table.LookupMatches{};

    for (self.tables.items) |table| {
        var matches = try table.lookup(abbr);
        try list.appendSlice(self.gpa, matches.items);
        matches.clearAndFree(self.gpa);
    }

    return list;
}

/// Creates an iterator of rows of all tables.
pub fn iterate(self: *Self) !Iterator {
    return try Iterator.create(self);
}

pub const Iterator = struct {
    database: *Self,
    iterator: *Table.RowIterator,
    index: *usize,

    pub fn create(database: *Self) !Iterator {
        const iterator = try database.gpa.create(Table.RowIterator);
        iterator.* = try database.tables.items[0].iterate();
        const index = try database.gpa.create(usize);
        index.* = 0;

        return .{
            .database = database,
            .iterator = iterator,
            .index = index,
        };
    }

    pub fn destroy(self: *Iterator) void {
        self.database.gpa.destroy(self.index);
        self.database.gpa.destroy(self.iterator);
    }

    pub fn next(self: *Iterator) !?*Table.Row {
        if (try self.iterator.next()) |row| return row else {
            self.index.* += 1;
            if (self.index.* == self.database.tables.items.len) return null;
            var table = self.database.tables.items[self.index.*];
            self.iterator.* = try table.iterate();

            // Discard head of all tables that are not the first table.
            const head = try self.iterator.next() orelse return null;
            head.destroy(self.database.gpa);

            return try self.iterator.next();
        }
    }
};

test iterate {
    const allocator = testing.allocator;

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var file_1 = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer file_1.close();

    var table = try Table.create(allocator, &file_1);
    errdefer table.destroy();

    var file_2_text = try test_utils.createTableText(
        allocator,
        &test_utils.TABLE_2,
    );
    defer file_2_text.clearAndFree(allocator);

    var file_2 = try test_utils.createFile(
        temp_dir.dir,
        "data_2.csv",
        file_2_text.items,
    );
    errdefer file_2.close();

    var table_2 = try Table.create(allocator, &file_2);
    errdefer table_2.destroy();

    var database = try create(allocator);
    defer database.destroy();
    try database.tables.appendSlice(&.{ &table, &table_2 });

    var iterator = try database.iterate();
    defer iterator.destroy();

    const tables = [2]test_utils.Table{
        &test_utils.TABLE,
        test_utils.TABLE_2[1..],
    };

    for (tables) |t| {
        for (t) |expected| {
            const row = try iterator.next();
            errdefer if (row) |r| r.destroy(allocator);

            try testing.expect(row != null);

            if (row) |r| {
                try testing.expectEqualStrings(expected[0], r.get_abbreviation());
                try testing.expectEqualStrings(expected[1], r.get_expansion());
                try testing.expectEqualStrings(expected[2], r.get_category());
                r.destroy(allocator);
            }
        }
    }

    temp_dir.cleanup();
    file_1.close();
    file_2.close();
    table.destroy();
    table_2.destroy();
}

test lookup {
    const allocator = testing.allocator;

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var file = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer file.close();

    var table = try Table.create(allocator, &file);
    errdefer table.destroy();

    var database = try create(allocator);
    defer database.destroy();
    try database.tables.append(&table);

    var matches = try database.lookup("AI");
    defer {
        for (matches.items) |row| row.destroy(allocator);
        matches.clearAndFree(allocator);
    }

    try testing.expectEqual(1, matches.items.len);
    const row = matches.items[0];
    try testing.expect(row.match("AI"));

    temp_dir.cleanup();
    file.close();
    table.destroy();
}
