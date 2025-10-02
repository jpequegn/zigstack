const std = @import("std");

// ============================================================================
// Content Metadata Types
// ============================================================================

/// Image metadata
pub const ImageMetadata = struct {
    width: u32,
    height: u32,
    format: []const u8,
    color_depth: u8,

    pub fn deinit(self: *ImageMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.format);
    }
};

/// Video metadata
pub const VideoMetadata = struct {
    width: u32,
    height: u32,
    duration_seconds: f64,
    codec: []const u8,
    format: []const u8,

    pub fn deinit(self: *VideoMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.codec);
        allocator.free(self.format);
    }
};

/// Audio metadata
pub const AudioMetadata = struct {
    duration_seconds: f64,
    bitrate: u32,
    sample_rate: u32,
    format: []const u8,

    pub fn deinit(self: *AudioMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.format);
    }
};

/// Document metadata
pub const DocumentMetadata = struct {
    word_count: usize,
    line_count: usize,
    page_count: ?usize, // Only for PDFs

    pub fn deinit(_: *DocumentMetadata, _: std.mem.Allocator) void {
        // No heap allocations to free
    }
};

/// Code metadata
pub const CodeMetadata = struct {
    line_count: usize,
    blank_lines: usize,
    comment_lines: usize,
    code_lines: usize,
    language: []const u8,

    pub fn deinit(self: *CodeMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.language);
    }
};

/// Union type for all content metadata
pub const ContentMetadata = union(enum) {
    image: ImageMetadata,
    video: VideoMetadata,
    audio: AudioMetadata,
    document: DocumentMetadata,
    code: CodeMetadata,
    none,

    pub fn deinit(self: *ContentMetadata, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .image => |*img| img.deinit(allocator),
            .video => |*vid| vid.deinit(allocator),
            .audio => |*aud| aud.deinit(allocator),
            .document => |*doc| doc.deinit(allocator),
            .code => |*code| code.deinit(allocator),
            .none => {},
        }
    }
};

// ============================================================================
// Image Metadata Reader
// ============================================================================

/// Read PNG metadata from file header
pub fn readPngMetadata(allocator: std.mem.Allocator, file: std.fs.File) !ImageMetadata {
    // PNG signature: 89 50 4E 47 0D 0A 1A 0A
    var sig: [8]u8 = undefined;
    _ = try file.read(&sig);

    if (!std.mem.eql(u8, &sig, &[_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A })) {
        return error.InvalidFormat;
    }

    // Read IHDR chunk (first chunk after signature)
    // Skip chunk length (4 bytes) and chunk type (4 bytes)
    try file.seekTo(16);

    var ihdr: [13]u8 = undefined;
    _ = try file.read(&ihdr);

    const width = std.mem.readInt(u32, ihdr[0..4], .big);
    const height = std.mem.readInt(u32, ihdr[4..8], .big);
    const bit_depth = ihdr[8];

    return ImageMetadata{
        .width = width,
        .height = height,
        .format = try allocator.dupe(u8, "PNG"),
        .color_depth = bit_depth,
    };
}

/// Read JPEG metadata from file header
pub fn readJpegMetadata(allocator: std.mem.Allocator, file: std.fs.File) !ImageMetadata {
    // JPEG signature: FF D8
    var sig: [2]u8 = undefined;
    _ = try file.read(&sig);

    if (!std.mem.eql(u8, &sig, &[_]u8{ 0xFF, 0xD8 })) {
        return error.InvalidFormat;
    }

    // Scan for SOF0 (Start of Frame, Baseline DCT) marker: FF C0
    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: u8 = 0;

    while (true) {
        var marker: [2]u8 = undefined;
        const bytes_read = try file.read(&marker);
        if (bytes_read < 2) break;

        if (marker[0] != 0xFF) continue;

        // SOF0 marker found
        if (marker[1] == 0xC0) {
            var sof: [17]u8 = undefined;
            _ = try file.read(&sof);

            bit_depth = sof[2]; // Precision
            height = std.mem.readInt(u16, sof[3..5], .big);
            width = std.mem.readInt(u16, sof[5..7], .big);
            break;
        }

        // Skip to next marker
        var len_buf: [2]u8 = undefined;
        const len_read = try file.read(&len_buf);
        if (len_read < 2) break;

        const segment_len = std.mem.readInt(u16, &len_buf, .big);
        if (segment_len < 2) break;

        try file.seekBy(segment_len - 2);
    }

    if (width == 0 or height == 0) {
        return error.InvalidFormat;
    }

    return ImageMetadata{
        .width = width,
        .height = height,
        .format = try allocator.dupe(u8, "JPEG"),
        .color_depth = bit_depth,
    };
}

/// Read image metadata based on file extension
pub fn readImageMetadata(allocator: std.mem.Allocator, path: []const u8, extension: []const u8) !ImageMetadata {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var lower_ext_buf: [16]u8 = undefined;
    const lower_ext = std.ascii.lowerString(&lower_ext_buf, extension);

    if (std.mem.eql(u8, lower_ext, ".png")) {
        return readPngMetadata(allocator, file);
    } else if (std.mem.eql(u8, lower_ext, ".jpg") or std.mem.eql(u8, lower_ext, ".jpeg")) {
        return readJpegMetadata(allocator, file);
    }

    return error.UnsupportedFormat;
}

// ============================================================================
// Document Metadata Reader
// ============================================================================

/// Read document metadata for text files
pub fn readDocumentMetadata(allocator: std.mem.Allocator, path: []const u8) !DocumentMetadata {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_file_size = 10 * 1024 * 1024; // 10 MB limit
    const contents = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(contents);

    var word_count: usize = 0;
    var line_count: usize = 0;
    var in_word = false;

    for (contents) |c| {
        if (c == '\n') {
            line_count += 1;
        }

        if (std.ascii.isWhitespace(c)) {
            if (in_word) {
                word_count += 1;
                in_word = false;
            }
        } else {
            in_word = true;
        }
    }

    // Count last word if file doesn't end with whitespace
    if (in_word) {
        word_count += 1;
    }

    // Count last line if file doesn't end with newline
    if (contents.len > 0 and contents[contents.len - 1] != '\n') {
        line_count += 1;
    }

    return DocumentMetadata{
        .word_count = word_count,
        .line_count = line_count,
        .page_count = null, // PDF support would require external library
    };
}

// ============================================================================
// Code Metadata Reader
// ============================================================================

/// Detect programming language from file extension
pub fn detectLanguage(allocator: std.mem.Allocator, extension: []const u8) ![]const u8 {
    var lower_ext_buf: [16]u8 = undefined;
    const lower_ext = std.ascii.lowerString(&lower_ext_buf, extension);

    const lang = if (std.mem.eql(u8, lower_ext, ".zig"))
        "Zig"
    else if (std.mem.eql(u8, lower_ext, ".py"))
        "Python"
    else if (std.mem.eql(u8, lower_ext, ".js"))
        "JavaScript"
    else if (std.mem.eql(u8, lower_ext, ".ts"))
        "TypeScript"
    else if (std.mem.eql(u8, lower_ext, ".c"))
        "C"
    else if (std.mem.eql(u8, lower_ext, ".cpp") or std.mem.eql(u8, lower_ext, ".cc"))
        "C++"
    else if (std.mem.eql(u8, lower_ext, ".h"))
        "C Header"
    else if (std.mem.eql(u8, lower_ext, ".hpp") or std.mem.eql(u8, lower_ext, ".hh"))
        "C++ Header"
    else if (std.mem.eql(u8, lower_ext, ".java"))
        "Java"
    else if (std.mem.eql(u8, lower_ext, ".cs"))
        "C#"
    else if (std.mem.eql(u8, lower_ext, ".go"))
        "Go"
    else if (std.mem.eql(u8, lower_ext, ".rs"))
        "Rust"
    else if (std.mem.eql(u8, lower_ext, ".sh"))
        "Shell"
    else if (std.mem.eql(u8, lower_ext, ".bat"))
        "Batch"
    else
        "Unknown";

    return try allocator.dupe(u8, lang);
}

/// Read code metadata for source files
pub fn readCodeMetadata(allocator: std.mem.Allocator, path: []const u8, extension: []const u8) !CodeMetadata {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_file_size = 10 * 1024 * 1024; // 10 MB limit
    const contents = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(contents);

    var line_count: usize = 0;
    var blank_lines: usize = 0;
    var comment_lines: usize = 0;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        line_count += 1;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            blank_lines += 1;
            continue;
        }

        // Simple comment detection (line starts with // or #)
        if (std.mem.startsWith(u8, trimmed, "//") or std.mem.startsWith(u8, trimmed, "#")) {
            comment_lines += 1;
        }
    }

    const code_lines = line_count - blank_lines - comment_lines;
    const language = try detectLanguage(allocator, extension);

    return CodeMetadata{
        .line_count = line_count,
        .blank_lines = blank_lines,
        .comment_lines = comment_lines,
        .code_lines = code_lines,
        .language = language,
    };
}

// ============================================================================
// Main Content Metadata Reader
// ============================================================================

/// Read content metadata for any supported file type
pub fn readContentMetadata(allocator: std.mem.Allocator, path: []const u8, extension: []const u8, category: anytype) !ContentMetadata {
    const CategoryType = @TypeOf(category);

    // Image files
    if (category == CategoryType.Images) {
        if (readImageMetadata(allocator, path, extension)) |metadata| {
            return ContentMetadata{ .image = metadata };
        } else |_| {
            return ContentMetadata.none;
        }
    }

    // Document files
    if (category == CategoryType.Documents) {
        if (readDocumentMetadata(allocator, path)) |metadata| {
            return ContentMetadata{ .document = metadata };
        } else |_| {
            return ContentMetadata.none;
        }
    }

    // Code files
    if (category == CategoryType.Code) {
        if (readCodeMetadata(allocator, path, extension)) |metadata| {
            return ContentMetadata{ .code = metadata };
        } else |_| {
            return ContentMetadata.none;
        }
    }

    // Audio and video would require external libraries or more complex parsing
    // For now, return none for unsupported types
    return ContentMetadata.none;
}

// ============================================================================
// Tests
// ============================================================================

test "detect language from extension" {
    const allocator = std.testing.allocator;

    const lang = try detectLanguage(allocator, ".zig");
    defer allocator.free(lang);
    try std.testing.expectEqualStrings("Zig", lang);
}

test "document metadata with empty file" {
    const allocator = std.testing.allocator;

    // Create temporary test file
    const test_path = "/tmp/zigstack_test_doc.txt";
    const file = try std.fs.cwd().createFile(test_path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const metadata = try readDocumentMetadata(allocator, test_path);
    try std.testing.expectEqual(@as(usize, 0), metadata.word_count);
    try std.testing.expectEqual(@as(usize, 0), metadata.line_count);
}

test "document metadata with simple text" {
    const allocator = std.testing.allocator;

    const test_path = "/tmp/zigstack_test_doc2.txt";
    const file = try std.fs.cwd().createFile(test_path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    try file.writeAll("Hello world\nThis is a test\n");

    const metadata = try readDocumentMetadata(allocator, test_path);
    try std.testing.expectEqual(@as(usize, 6), metadata.word_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.line_count);
}

test "code metadata" {
    const allocator = std.testing.allocator;

    const test_path = "/tmp/zigstack_test_code.zig";
    const file = try std.fs.cwd().createFile(test_path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(test_path) catch {};

    try file.writeAll(
        \\const std = @import("std");
        \\
        \\// This is a comment
        \\pub fn main() void {
        \\    std.debug.print("Hello\n", .{});
        \\}
    );

    var metadata = try readCodeMetadata(allocator, test_path, ".zig");
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 6), metadata.line_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.blank_lines);
    try std.testing.expectEqual(@as(usize, 1), metadata.comment_lines);
    try std.testing.expectEqual(@as(usize, 4), metadata.code_lines);
    try std.testing.expectEqualStrings("Zig", metadata.language);
}
