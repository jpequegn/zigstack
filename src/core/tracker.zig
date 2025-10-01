const std = @import("std");
const print = std.debug.print;
const config_mod = @import("config.zig");

pub const Config = config_mod.Config;

pub const MoveRecord = struct {
    original_path: []const u8,
    destination_path: []const u8,
};

pub const MoveTracker = struct {
    moves: std.ArrayList(MoveRecord),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MoveTracker {
        return MoveTracker{
            .moves = std.ArrayList(MoveRecord){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MoveTracker) void {
        for (self.moves.items) |move_record| {
            self.allocator.free(move_record.original_path);
            self.allocator.free(move_record.destination_path);
        }
        self.moves.deinit(self.allocator);
    }

    pub fn recordMove(self: *MoveTracker, original_path: []const u8, destination_path: []const u8) !void {
        const original_copy = try self.allocator.dupe(u8, original_path);
        const destination_copy = try self.allocator.dupe(u8, destination_path);

        try self.moves.append(self.allocator, MoveRecord{
            .original_path = original_copy,
            .destination_path = destination_copy,
        });
    }

    pub fn rollback(self: *MoveTracker, config: *const Config) !void {
        if (config.verbose) {
            print("Rolling back {} file moves...\n", .{self.moves.items.len});
        }

        // Rollback in reverse order
        var i = self.moves.items.len;
        while (i > 0) {
            i -= 1;
            const move_record = self.moves.items[i];

            if (config.verbose) {
                print("Moving {s} back to {s}\n", .{ move_record.destination_path, move_record.original_path });
            }

            std.fs.cwd().rename(move_record.destination_path, move_record.original_path) catch |err| {
                print("Error: Failed to rollback file move\n", .{});
                print("Could not move {s} back to {s}: {}\n", .{ move_record.destination_path, move_record.original_path, err });
                return err;
            };
        }

        if (config.verbose) {
            print("Rollback complete.\n", .{});
        }
    }
};
