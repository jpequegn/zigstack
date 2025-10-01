const std = @import("std");

pub const FileCategory = enum {
    Documents,
    Images,
    Videos,
    Audio,
    Archives,
    Code,
    Data,
    Configuration,
    Other,

    pub fn toString(self: FileCategory) []const u8 {
        return switch (self) {
            .Documents => "Documents",
            .Images => "Images",
            .Videos => "Videos",
            .Audio => "Audio",
            .Archives => "Archives",
            .Code => "Code",
            .Data => "Data",
            .Configuration => "Configuration",
            .Other => "Other",
        };
    }

    pub fn toDirectoryName(self: FileCategory) []const u8 {
        return switch (self) {
            .Documents => "documents",
            .Images => "images",
            .Videos => "videos",
            .Audio => "audio",
            .Archives => "archives",
            .Code => "code",
            .Data => "data",
            .Configuration => "config",
            .Other => "misc",
        };
    }
};

pub const FileInfo = struct {
    name: []const u8,
    extension: []const u8,
    category: FileCategory,

    // Advanced organization fields
    size: u64, // File size in bytes for size-based organization
    created_time: i64, // Unix timestamp for creation time
    modified_time: i64, // Unix timestamp for modification time
    hash: [32]u8, // SHA-256 hash for duplicate detection
};
