const std = @import("std");
const file_info = @import("file_info.zig");

pub const FileInfo = file_info.FileInfo;
pub const FileCategory = file_info.FileCategory;

pub const OrganizationPlan = struct {
    categories: std.hash_map.HashMap(FileCategory, std.ArrayList(FileInfo), std.hash_map.AutoContext(FileCategory), 80),
    // For date-based and custom organization - maps directory path to files
    directories: std.StringHashMap(std.ArrayList(FileInfo)),
    total_files: usize,
    is_date_based: bool = false, // Track organization type
    is_size_based: bool = false, // Track size-based organization
};
