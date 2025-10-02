const std = @import("std");

// ============================================================================
// Export Format Types
// ============================================================================

/// Supported export formats
pub const ExportFormat = enum {
    json,
    csv,

    pub fn fromString(s: []const u8) !ExportFormat {
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "csv")) return .csv;
        return error.InvalidFormat;
    }

    pub fn toString(self: ExportFormat) []const u8 {
        return switch (self) {
            .json => "json",
            .csv => "csv",
        };
    }

    pub fn getFileExtension(self: ExportFormat) []const u8 {
        return switch (self) {
            .json => ".json",
            .csv => ".csv",
        };
    }
};

// ============================================================================
// Export Writer
// ============================================================================

/// Generic export writer that handles file creation and formatting
pub const ExportWriter = struct {
    allocator: std.mem.Allocator,
    format: ExportFormat,
    output_path: ?[]const u8,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, format: ExportFormat, output_path: ?[]const u8) ExportWriter {
        return ExportWriter{
            .allocator = allocator,
            .format = format,
            .output_path = output_path,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ExportWriter) void {
        self.buffer.deinit();
    }

    /// Write formatted data to output
    pub fn write(self: *ExportWriter, data: []const u8) !void {
        if (self.output_path) |path| {
            // Write to file
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(data);
        } else {
            // Write to stdout
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(data);
        }
    }
};

// ============================================================================
// JSON Export Utilities
// ============================================================================

/// JSON writer helper for building JSON strings
pub const JsonWriter = struct {
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) JsonWriter {
        return JsonWriter{ .buffer = buffer, .allocator = allocator };
    }

    pub fn writeObjectStart(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, '{');
    }

    pub fn writeObjectEnd(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, '}');
    }

    pub fn writeArrayStart(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, '[');
    }

    pub fn writeArrayEnd(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, ']');
    }

    pub fn writeComma(self: *JsonWriter) !void {
        try self.buffer.append(self.allocator, ',');
    }

    pub fn writeKey(self: *JsonWriter, key: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        try self.buffer.appendSlice(self.allocator, key);
        try self.buffer.appendSlice(self.allocator, "\":");
    }

    pub fn writeString(self: *JsonWriter, value: []const u8) !void {
        try self.buffer.append(self.allocator, '"');
        // Escape special characters
        for (value) |c| {
            switch (c) {
                '"' => try self.buffer.appendSlice(self.allocator, "\\\""),
                '\\' => try self.buffer.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try self.buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try self.buffer.appendSlice(self.allocator, "\\t"),
                else => try self.buffer.append(self.allocator, c),
            }
        }
        try self.buffer.append(self.allocator, '"');
    }

    pub fn writeNumber(self: *JsonWriter, value: anytype) !void {
        const writer = self.buffer.writer(self.allocator);
        try std.fmt.format(writer, "{d}", .{value});
    }

    pub fn writeBool(self: *JsonWriter, value: bool) !void {
        if (value) {
            try self.buffer.appendSlice(self.allocator, "true");
        } else {
            try self.buffer.appendSlice(self.allocator, "false");
        }
    }

    pub fn writeKeyValue(self: *JsonWriter, key: []const u8, value: []const u8) !void {
        try self.writeKey(key);
        try self.writeString(value);
    }

    pub fn writeKeyNumber(self: *JsonWriter, key: []const u8, value: anytype) !void {
        try self.writeKey(key);
        try self.writeNumber(value);
    }
};

// ============================================================================
// CSV Export Utilities
// ============================================================================

/// CSV writer helper for building CSV strings
pub const CsvWriter = struct {
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    field_count: usize,
    current_field: usize,

    pub fn init(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) CsvWriter {
        return CsvWriter{
            .buffer = buffer,
            .allocator = allocator,
            .field_count = 0,
            .current_field = 0,
        };
    }

    pub fn writeHeader(self: *CsvWriter, headers: []const []const u8) !void {
        for (headers) |header| {
            try self.writeField(header);
        }
        try self.buffer.append(self.allocator, '\n');
        self.field_count = headers.len;
        self.current_field = 0; // Reset for data rows
    }

    pub fn writeRow(self: *CsvWriter) !void {
        try self.buffer.append(self.allocator, '\n');
        self.current_field = 0;
    }

    pub fn writeField(self: *CsvWriter, value: []const u8) !void {
        if (self.current_field > 0) {
            try self.buffer.append(self.allocator, ',');
        }

        // Check if field needs quoting (contains comma, quote, or newline)
        var needs_quoting = false;
        for (value) |c| {
            if (c == ',' or c == '"' or c == '\n' or c == '\r') {
                needs_quoting = true;
                break;
            }
        }

        if (needs_quoting) {
            try self.buffer.append(self.allocator, '"');
            for (value) |c| {
                if (c == '"') {
                    try self.buffer.appendSlice(self.allocator, "\"\""); // Escape quotes
                } else {
                    try self.buffer.append(self.allocator, c);
                }
            }
            try self.buffer.append(self.allocator, '"');
        } else {
            try self.buffer.appendSlice(self.allocator, value);
        }

        self.current_field += 1;
    }

    pub fn writeFieldNumber(self: *CsvWriter, value: anytype) !void {
        var buf: [64]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buf, "{d}", .{value});
        try self.writeField(formatted);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ExportFormat from/to string" {
    const json = try ExportFormat.fromString("json");
    try std.testing.expectEqual(ExportFormat.json, json);
    try std.testing.expectEqualStrings("json", json.toString());

    const csv = try ExportFormat.fromString("csv");
    try std.testing.expectEqual(ExportFormat.csv, csv);
    try std.testing.expectEqualStrings("csv", csv.toString());
}

test "JsonWriter basic operations" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8){
        .items = &[_]u8{},
        .capacity = 0,
    };
    defer buffer.deinit(allocator);

    var writer = JsonWriter.init(&buffer, allocator);

    try writer.writeObjectStart();
    try writer.writeKeyValue("name", "test");
    try writer.writeComma();
    try writer.writeKeyNumber("count", 42);
    try writer.writeObjectEnd();

    try std.testing.expectEqualStrings("{\"name\":\"test\",\"count\":42}", buffer.items);
}

test "CsvWriter basic operations" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8){
        .items = &[_]u8{},
        .capacity = 0,
    };
    defer buffer.deinit(allocator);

    var writer = CsvWriter.init(&buffer, allocator);

    const headers = [_][]const u8{ "Name", "Count" };
    try writer.writeHeader(&headers);

    try writer.writeField("test");
    try writer.writeFieldNumber(42);
    try writer.writeRow();

    try writer.writeField("example");
    try writer.writeFieldNumber(100);

    const expected = "Name,Count\ntest,42\nexample,100";
    try std.testing.expectEqualStrings(expected, buffer.items);
}
