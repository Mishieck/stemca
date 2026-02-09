const std = @import("std");
const heap = std.heap;
const debug = std.debug;
const mem = std.mem;
const fmt = std.fmt;
const process = std.process;
const testing = std.testing;
const File = std.fs.File;

const lib = @import("abbreviations");
const Database = lib.Database;
const fs = lib.fs;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);

    var arena = heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const gpa_alloc = gpa.allocator();
    const arena_alloc = arena.allocator();
    const Iterator = Database.ListRowIterator;
    const iterator = Iterator.init(arena_alloc, &.{});

    const db = try Database.fromIterator(Iterator.Data, arena_alloc, iterator);
    errdefer db.destroy();

    var args = try std.process.ArgIterator.initWithAllocator(gpa_alloc);
    defer args.deinit();

    try runCommand(arena_alloc, db, &args);

    db.destroy();
}

fn runCommand(
    arena: mem.Allocator,
    db: *Database,
    args: *process.ArgIterator,
) !void {
    _ = args.next();
    const command_name = args.next() orelse return error.NoCommand;

    const command = Command.fromString(command_name) catch |err| {
        if (err == error.NotCommand) {
            // TODO: Use `stderr`.
            debug.print("'{s}' is not a valid command.", .{command_name});
        }

        return err;
    };

    switch (command) {
        .list => try list(arena, db),
        .lookup => {
            const abbr = args.next() orelse return error.MissingAbbreviation;
            try lookup(arena, db, abbr);
        },
        .update => try update(arena, db),
    }
}

const Command = enum {
    list,
    lookup,
    update,

    pub fn fromString(string: []const u8) !Command {
        const map = [_]struct { []const u8, Command }{
            .{ "list", .list },
            .{ "lookup", .lookup },
            .{ "update", .update },
        };

        return for (map) |entry| {
            const key, const value = entry;
            if (mem.eql(u8, key, string)) break value else continue;
        } else return error.NotCommand;
    }
};

fn openDatabaseFile(
    allocator: mem.Allocator,
    comptime createIfNotFound: bool,
    mode: std.fs.File.OpenMode,
    dir: std.fs.Dir,
    path: []const u8,
) !*std.fs.File {
    const open_flags = std.fs.File.OpenFlags{ .mode = mode };
    const file = try allocator.create(std.fs.File);

    file.* = dir.openFile(path, open_flags) catch |err| err: {
        if (createIfNotFound and err == error.FileNotFound) {
            break :err try dir.createFile(path, .{});
        }

        return err;
    };

    return file;
}

/// Updates the database using contributions. It bundles all contributtions
/// into one file.
fn update(arena: mem.Allocator, db: *Database) !void {
    const cwd = std.fs.cwd();
    const db_path = fs.uriRefToNativePath("./database/");
    var db_dir = try cwd.openDir(db_path, .{});
    var cont_dir = try db_dir.openDir("contributions", .{ .iterate = true });
    var cont_iter = cont_dir.iterate();

    while (try cont_iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const iter = try fs.createFileRowIterator(arena, cont_dir, entry.name);
                try db.mergeIterator(*fs.FileRowIteratorData, iter);
            },
            else => {},
        }
    }

    const table = try db.toCsvTable();

    const db_file_path = fs.uriRefToNativePath("./database/data.csv");
    try db_dir.writeFile(.{ .data = table, .sub_path = "data.csv" });

    debug.print("Successfully updated database at {s}\n", .{db_file_path});
}

/// Finds and displays matches of an abbreviation.
fn lookup(arena: mem.Allocator, db: *Database, abbr: []const u8) !void {
    const exe_path = try std.fs.selfExeDirPathAlloc(arena);
    const exec_dir = try std.fs.cwd().openDir(exe_path, .{});
    const db_path = fs.uriRefToNativePath("./database/data.csv");

    const iterator = try fs.createFileRowIterator(arena, exec_dir, db_path);
    try db.mergeIterator(*fs.FileRowIteratorData, iterator);

    const matches = try db.matchAbbreviation(abbr);

    if (matches.len > 0) {
        const template =
            \\
            \\{} match{s} found
            \\
            \\{s}
        ;

        var match_list = std.ArrayList(u8){};

        for (matches) |row| {
            const formatted = try row.format(arena);
            try match_list.appendSlice(arena, formatted);
        }

        const plural = if (matches.len > 1) "es" else "";

        const message = try fmt.allocPrint(
            arena,
            template,
            .{ matches.len, plural, match_list.items },
        );

        defer arena.free(message);
        const stdout = File.stdout();
        try stdout.writeAll(message);
    } else {
        const stderr = File.stderr();
        const template = "No matches found for '{s}'!\n";
        const message = try fmt.allocPrint(arena, template, .{abbr});
        defer arena.free(message);
        try stderr.writeAll(message);
    }
}

/// Displays a table of all the abbreviations in the database.
fn list(arena: mem.Allocator, db: *Database) !void {
    const exe_path = try std.fs.selfExeDirPathAlloc(arena);
    const exec_dir = try std.fs.cwd().openDir(exe_path, .{});
    const db_path = fs.uriRefToNativePath("./database/data.csv");

    const iterator = try fs.createFileRowIterator(arena, exec_dir, db_path);
    try db.mergeIterator(*fs.FileRowIteratorData, iterator);

    if (db.rows.items.len == 0) {
        const stderr = File.stderr();
        try stderr.writeAll("Database is empty!\n");
        return;
    }

    const heading_cells = [3][]const u8{
        "Abbreviation",
        "Expansion",
        "Category",
    };

    var column_sizes: [3]usize = undefined;
    for (0..3) |i| column_sizes[i] = heading_cells[i].len;

    const gap = 4;

    for (db.rows.items) |row| {
        for (column_sizes, 0..) |max, i| {
            const length = row.array.items[i].len;
            if (max < length) column_sizes[i] = length;
        }
    }

    const stdout = File.stdout();
    errdefer stdout.close();

    for (column_sizes, 0..) |size, i| column_sizes[i] = size + gap;
    var total_table_length: usize = 0;
    for (column_sizes) |size| total_table_length += size;
    total_table_length -= gap;

    const heading_csv_row = try mem.join(arena, ",", &heading_cells);
    const heading = try Database.Row.fromString(arena, heading_csv_row);
    const heading_table_row = try heading.toTableRow(arena, column_sizes);

    _ = try stdout.write("\n");
    _ = try stdout.write(heading_table_row);
    var divider = try Database.repeatString(arena, "-", total_table_length);
    divider = try mem.concat(arena, u8, &.{ divider, "\n" });
    _ = try stdout.write(divider);

    for (db.rows.items) |row| {
        _ = try stdout.write(try row.toTableRow(arena, column_sizes));
    }

    stdout.close();
}
