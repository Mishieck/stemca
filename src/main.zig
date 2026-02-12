const std = @import("std");
const heap = std.heap;
const debug = std.debug;
const mem = std.mem;
const fmt = std.fmt;
const array_list = std.array_list;
const process = std.process;
const testing = std.testing;
const File = std.fs.File;

const format_utils = @import("format");
const lib = @import("stemca");
const Database = lib.Database;
const fs = lib.fs;
const test_utils = @import("test_utils");

const FileList = array_list.Managed(*std.fs.File);

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    errdefer args.deinit();

    try runCommand(&args);

    args.deinit();
}

fn runCommand(args: *process.ArgIterator) !void {
    _ = args.next(); // Discard executable path.
    const command_name = args.next() orelse return error.NoCommand;

    const command = Command.fromString(command_name) catch |err| {
        if (err == error.NotCommand) {
            // TODO: Use `stderr`.
            debug.print("'{s}' is not a valid command.", .{command_name});
        }

        return err;
    };

    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);
    const paths = [_][]const u8{ exe_path, "database", "tables", "" };
    const table_path = try std.fs.path.join(allocator, &paths);
    defer allocator.free(table_path);
    var table_dir = try std.fs.cwd().openDir(table_path, .{ .iterate = true });
    errdefer table_dir.close();

    var files = FileList.init(allocator);
    var file_iterator = table_dir.iterate();

    while (try file_iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        var file = try table_dir.openFile(entry.name, .{ .mode = .read_write });
        try files.append(&file);
    }

    var tables = try convertFilesToTables(allocator, files);
    var db = Database{ .gpa = allocator, .tables = &tables };

    errdefer for (files.items) |file| {
        file.close();
        allocator.destroy(file);
    };

    defer {
        files.clearAndFree();

        for (tables.items) |table| {
            table.destroy();
            allocator.destroy(table);
        }

        tables.clearAndFree();
    }

    var buffer: [1025]u8 = undefined;
    var stdout = std.fs.File.stdout();
    errdefer stdout.close();
    var stdout_writer = stdout.writer(&buffer);

    switch (command) {
        .list => try list(allocator, &stdout_writer, &db, tables),
        .lookup => {
            const abbr = args.next() orelse {
                const stderr = File.stderr();
                var writer = stderr.writer(&buffer);
                try writer.interface.writeAll("Missing abbreviation!\n");
                try writer.interface.flush();
                return error.MissingAbbreviation;
            };

            try lookup(allocator, &stdout_writer, &db, tables, abbr);
        },
        .verify => try verify(allocator, &stdout_writer, &tables),
    }

    for (files.items) |file| file.close();
    table_dir.close();
    stdout.close();
}

const Command = enum {
    list,
    lookup,
    verify,

    pub fn fromString(string: []const u8) !Command {
        const map = [_]struct { []const u8, Command }{
            .{ "list", .list },
            .{ "lookup", .lookup },
            .{ "verify", .verify },
        };

        return for (map) |entry| {
            const key, const value = entry;
            if (mem.eql(u8, key, string)) break value else continue;
        } else return error.NotCommand;
    }
};

/// Finds and displays matches of an abbreviation.
fn lookup(
    gpa: mem.Allocator,
    output: *std.fs.File.Writer,
    db: *Database,
    tables: Database.TableList,
    abbr: Database.Table.Row.Abbreviation,
) !void {
    db.tables.* = tables;
    var matches = try db.lookup(abbr);
    defer {
        for (matches.items) |row| row.destroy(gpa);
        matches.clearAndFree(gpa);
    }

    if (matches.items.len > 0) {
        const template =
            \\
            \\{} match{s} found
            \\
            \\{s}
        ;

        var match_list = array_list.Managed(u8).init(gpa);
        defer match_list.clearAndFree();

        for (matches.items) |row| {
            const formatted = try row.format(gpa);
            defer gpa.free(formatted);
            try match_list.appendSlice(formatted);
        }

        const plural = if (matches.items.len > 1) "es" else "";

        const message = try fmt.allocPrint(
            gpa,
            template,
            .{ matches.items.len, plural, match_list.items },
        );

        defer gpa.free(message);
        _ = try output.interface.write(message);
        try output.interface.flush();
    } else {
        const template = "No matches found for '{s}'!\n";
        const message = try fmt.allocPrint(gpa, template, .{abbr});
        defer gpa.free(message);
        const stderr = File.stderr();
        var buffer: [1024]u8 = undefined;
        var writer = stderr.writer(&buffer);
        try writer.interface.writeAll(message);
        try writer.interface.flush();
        stderr.close();
    }
}

/// Displays a table of all the abbreviations in the database.
fn list(
    gpa: mem.Allocator,
    output: *std.fs.File.Writer,
    db: *Database,
    tables: Database.TableList,
) !void {
    db.tables.* = tables;
    var iterator = try db.iterate();
    var head = try iterator.next() orelse return error.DatabaseEmpty;

    const head_cells = [3][]const u8{
        head.get_abbreviation(),
        head.get_expansion(),
        head.get_category(),
    };

    var column_sizes: [3]usize = undefined;
    for (0..3) |i| column_sizes[i] = head_cells[i].len;

    const gap = 4;

    while (try iterator.next()) |row| {
        defer row.destroy(gpa);

        const cells = [3][]const u8{
            row.get_abbreviation(),
            row.get_expansion(),
            row.get_category(),
        };

        for (column_sizes, 0..) |max, i| {
            const length = cells[i].len;
            if (max < length) column_sizes[i] = length;
        }
    }

    for (column_sizes, 0..) |size, i| column_sizes[i] = size + gap;
    var total_table_length: usize = 0;
    for (column_sizes) |size| total_table_length += size;
    total_table_length -= gap;

    iterator.destroy();
    iterator = try db.iterate();
    defer iterator.destroy();
    head.destroy(gpa);
    head = try iterator.next() orelse unreachable;
    defer head.destroy(gpa);

    _ = try output.interface.write("\n");
    const head_table_row = try head.toTableRow(gpa, column_sizes);
    defer gpa.free(head_table_row);
    _ = try output.interface.write(head_table_row);
    const divider = try format_utils.repeatString(gpa, "-", total_table_length);

    defer gpa.free(divider);
    _ = try output.interface.write(divider);
    _ = try output.interface.write("\n");
    try output.interface.flush();

    while (try iterator.next()) |row| {
        defer row.destroy(gpa);
        const table_row = try row.toTableRow(gpa, column_sizes);
        defer gpa.free(table_row);
        _ = try output.interface.write(table_row);
        try output.interface.flush();
    }
}

/// Updates the database using contributions. It bundles all contributions into.
/// one file.
fn verify(
    gpa: mem.Allocator,
    output: *std.fs.File.Writer,
    tables: *Database.TableList,
) !void {
    const table_count = tables.items.len;

    if (table_count < 2) {
        const template = "{} {s} found. Verification successful!\n";

        const pluralized = try format_utils.pluralize(
            gpa,
            "table",
            "s",
            table_count,
        );
        defer gpa.free(pluralized);

        const message = try fmt.allocPrint(
            gpa,
            template,
            .{ tables.items.len, pluralized },
        );

        defer gpa.free(message);
        _ = try output.interface.write(message);
        try output.interface.flush();
        return;
    }

    var latest_table = tables.items[0];
    var latest_stat = try latest_table.file.stat();
    var i: usize = 0;

    for (tables.items, 0..) |table, j| {
        const stat = try table.file.stat();

        if (stat.mtime > latest_stat.mtime) {
            latest_table = table;
            latest_stat = stat;
            i = j;
        }
    }

    for (tables.items) |table| {
        if (table == latest_table) continue;

        var table_iterator = try latest_table.iterate();
        while (try table_iterator.next()) |row| {
            defer row.destroy(gpa);
            const abbr = row.get_abbreviation();

            var matches = try table.lookup(abbr);
            defer {
                for (matches.items) |r| r.destroy(gpa);
                matches.clearAndFree(gpa);
            }

            if (matches.items.len == 0) continue;

            var stderr = std.fs.File.stderr();
            defer stderr.close();
            var buffer: [1024]u8 = undefined;
            var stderr_writer = stderr.writer(&buffer);

            const formatted_row = try row.format(gpa);
            defer gpa.free(formatted_row);

            const message = try fmt.allocPrint(
                gpa,
                "Found a duplicate for '{s}'!\n\n{s}\n",
                .{ abbr, formatted_row },
            );

            defer gpa.free(message);
            try stderr_writer.interface.writeAll(message);
            try stderr_writer.interface.flush();

            return error.DuplicateFound;
        }
    }

    _ = try output.interface.write("Verification successful!\n");
    try output.interface.flush();
}

fn convertFilesToTables(
    gpa: mem.Allocator,
    files: FileList,
) !Database.TableList {
    var tables = Database.TableList.init(gpa);

    for (files.items) |file| {
        const table = try gpa.create(Database.Table);
        table.* = try Database.Table.create(gpa, file);
        try tables.append(table);
    }

    return tables;
}

test verify {
    const allocator = testing.allocator;

    var tables = Database.TableList.init(allocator);
    errdefer {
        for (tables.items) |t| t.destroy();
        tables.clearAndFree();
    }

    var temp_dir = testing.tmpDir(.{});
    errdefer temp_dir.cleanup();

    var file_1 = try test_utils.createDefaultFile(allocator, temp_dir.dir);
    errdefer file_1.close();

    var table = try Database.Table.create(allocator, &file_1);

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

    var output_dir = try temp_dir.dir.makeOpenPath("output", .{});
    defer output_dir.close();

    var output_file = try test_utils.createFile(output_dir, "output.txt", "");
    errdefer output_file.close();

    var table_2 = try Database.Table.create(allocator, &file_2);

    try tables.appendSlice(&.{ &table, &table_2 });
    defer tables.clearAndFree();

    var buffer: [1024]u8 = undefined;
    var output_writer = output_file.writer(&buffer);
    try verify(allocator, &output_writer, &tables);

    var reader = output_file.reader(&buffer);
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    defer alloc_writer.deinit();
    _ = try reader.interface.streamRemaining(&alloc_writer.writer);
    const content = alloc_writer.written();
    const message_fragment = "Verification successful";
    const has_fragment = mem.indexOf(u8, content, message_fragment) != null;
    try testing.expect(has_fragment);

    var table_3 = try Database.Table.create(allocator, &file_2);

    try tables.append(&table_3);
    const result = verify(allocator, &output_writer, &tables);
    try testing.expectError(error.DuplicateFound, result);

    temp_dir.cleanup();
    file_1.close();
    file_2.close();
    for (tables.items) |t| t.destroy();
    tables.clearAndFree();
    output_file.close();
}
