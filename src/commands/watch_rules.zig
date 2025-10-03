const std = @import("std");
const print = std.debug.print;

const utils = @import("../core/utils.zig");
const file_info_mod = @import("../core/file_info.zig");

const FileInfo = file_info_mod.FileInfo;

/// Event triggers for rules
pub const Trigger = enum {
    file_created,
    file_modified,
    file_deleted,
    periodic,

    pub fn fromString(s: []const u8) ?Trigger {
        if (std.mem.eql(u8, s, "file_created")) return .file_created;
        if (std.mem.eql(u8, s, "file_modified")) return .file_modified;
        if (std.mem.eql(u8, s, "file_deleted")) return .file_deleted;
        if (std.mem.eql(u8, s, "periodic")) return .periodic;
        return null;
    }

    pub fn toString(self: Trigger) []const u8 {
        return switch (self) {
            .file_created => "file_created",
            .file_modified => "file_modified",
            .file_deleted => "file_deleted",
            .periodic => "periodic",
        };
    }
};

/// Pattern matcher for file matching
pub const Matcher = struct {
    pattern: ?[]const u8 = null, // Glob pattern (e.g., "*.pdf")
    path_contains: ?[]const u8 = null, // Path must contain this string
    path_regex: ?[]const u8 = null, // Regex pattern (not implemented yet)
    extension: ?[]const u8 = null, // Specific file extension

    pub fn matches(self: *const Matcher, file_path: []const u8) bool {
        // Check pattern (glob)
        if (self.pattern) |pattern| {
            if (!matchGlob(pattern, file_path)) return false;
        }

        // Check path contains
        if (self.path_contains) |substring| {
            if (std.mem.indexOf(u8, file_path, substring) == null) return false;
        }

        // Check extension
        if (self.extension) |ext| {
            const file_ext = utils.getFileExtension(file_path);
            if (!std.ascii.eqlIgnoreCase(file_ext, ext)) return false;
        }

        return true;
    }
};

/// Match a glob pattern against a string
pub fn matchGlob(pattern: []const u8, text: []const u8) bool {
    return matchGlobRecursive(pattern, text, 0, 0);
}

fn matchGlobRecursive(pattern: []const u8, text: []const u8, p_idx: usize, t_idx: usize) bool {
    // Base cases
    if (p_idx == pattern.len and t_idx == text.len) return true;
    if (p_idx == pattern.len) return false;

    const p_char = pattern[p_idx];

    if (p_char == '*') {
        // Try matching zero or more characters
        // First try matching zero characters
        if (matchGlobRecursive(pattern, text, p_idx + 1, t_idx)) return true;

        // Then try matching one or more characters
        if (t_idx < text.len) {
            return matchGlobRecursive(pattern, text, p_idx, t_idx + 1);
        }
        return false;
    } else if (p_char == '?') {
        // Match exactly one character
        if (t_idx >= text.len) return false;
        return matchGlobRecursive(pattern, text, p_idx + 1, t_idx + 1);
    } else {
        // Match exact character
        if (t_idx >= text.len or pattern[p_idx] != text[t_idx]) return false;
        return matchGlobRecursive(pattern, text, p_idx + 1, t_idx + 1);
    }
}

/// Condition types for rule evaluation
pub const Condition = union(enum) {
    size_gt: u64, // File size greater than (bytes)
    size_lt: u64, // File size less than (bytes)
    time_of_day: struct { // Time range (24-hour format)
        start_hour: u8,
        start_min: u8,
        end_hour: u8,
        end_min: u8,
    },
    age_gt: u64, // File age greater than (seconds)
    age_lt: u64, // File age less than (seconds)

    pub fn evaluate(self: *const Condition, file_path: []const u8, file_size: u64, file_mtime: i128) bool {
        switch (self.*) {
            .size_gt => |threshold| return file_size > threshold,
            .size_lt => |threshold| return file_size < threshold,
            .time_of_day => |time_range| {
                const now = std.time.timestamp();
                const epoch_secs = @as(u64, @intCast(@rem(now, 86400)));
                const hour = @as(u8, @intCast((epoch_secs / 3600) % 24));
                const minute = @as(u8, @intCast((epoch_secs % 3600) / 60));

                const current_mins = @as(u16, hour) * 60 + minute;
                const start_mins = @as(u16, time_range.start_hour) * 60 + time_range.start_min;
                const end_mins = @as(u16, time_range.end_hour) * 60 + time_range.end_min;

                return current_mins >= start_mins and current_mins <= end_mins;
            },
            .age_gt => |threshold| {
                const now = std.time.timestamp();
                const age = @as(u64, @intCast(now - @as(i64, @intCast(@divFloor(file_mtime, std.time.ns_per_s)))));
                return age > threshold;
            },
            .age_lt => |threshold| {
                const now = std.time.timestamp();
                const age = @as(u64, @intCast(now - @as(i64, @intCast(@divFloor(file_mtime, std.time.ns_per_s)))));
                return age < threshold;
            },
        }
        _ = file_path; // Unused for now
    }
};

/// Action types for rule execution
pub const Action = union(enum) {
    organize: struct {
        by_category: bool = false,
        by_date: bool = false,
        by_size: bool = false,
    },
    move: struct {
        destination: []const u8,
    },
    archive: struct {
        destination: []const u8,
        compress: bool = false,
    },
    delete: void,
    log: struct {
        message: []const u8,
    },

    pub fn execute(
        self: *const Action,
        allocator: std.mem.Allocator,
        file_path: []const u8,
        context: *ActionContext,
    ) !void {
        switch (self.*) {
            .organize => |opts| {
                try context.queueOrganize(allocator, file_path, opts);
            },
            .move => |opts| {
                try context.queueMove(allocator, file_path, opts.destination);
            },
            .archive => |opts| {
                try context.queueArchive(allocator, file_path, opts.destination, opts.compress);
            },
            .delete => {
                try context.queueDelete(allocator, file_path);
            },
            .log => |opts| {
                print("[Rule Action] {s}: {s}\n", .{ file_path, opts.message });
            },
        }
    }
};

/// Context for executing actions
pub const ActionContext = struct {
    organize_queue: std.ArrayListUnmanaged([]const u8),
    move_queue: std.ArrayListUnmanaged(MoveEntry),
    archive_queue: std.ArrayListUnmanaged(ArchiveEntry),
    delete_queue: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    const MoveEntry = struct {
        source: []const u8,
        destination: []const u8,
    };

    const ArchiveEntry = struct {
        source: []const u8,
        destination: []const u8,
        compress: bool,
    };

    pub fn init(allocator: std.mem.Allocator) ActionContext {
        return .{
            .organize_queue = std.ArrayListUnmanaged([]const u8){},
            .move_queue = std.ArrayListUnmanaged(MoveEntry){},
            .archive_queue = std.ArrayListUnmanaged(ArchiveEntry){},
            .delete_queue = std.ArrayListUnmanaged([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ActionContext) void {
        for (self.organize_queue.items) |path| {
            self.allocator.free(path);
        }
        self.organize_queue.deinit(self.allocator);

        for (self.move_queue.items) |entry| {
            self.allocator.free(entry.source);
            self.allocator.free(entry.destination);
        }
        self.move_queue.deinit(self.allocator);

        for (self.archive_queue.items) |entry| {
            self.allocator.free(entry.source);
            self.allocator.free(entry.destination);
        }
        self.archive_queue.deinit(self.allocator);

        for (self.delete_queue.items) |path| {
            self.allocator.free(path);
        }
        self.delete_queue.deinit(self.allocator);
    }

    fn queueOrganize(self: *ActionContext, allocator: std.mem.Allocator, file_path: []const u8, opts: anytype) !void {
        _ = opts; // Will be used when implementing organize logic
        try self.organize_queue.append(self.allocator, try allocator.dupe(u8, file_path));
    }

    fn queueMove(self: *ActionContext, allocator: std.mem.Allocator, source: []const u8, destination: []const u8) !void {
        try self.move_queue.append(self.allocator, .{
            .source = try allocator.dupe(u8, source),
            .destination = try allocator.dupe(u8, destination),
        });
    }

    fn queueArchive(self: *ActionContext, allocator: std.mem.Allocator, source: []const u8, destination: []const u8, compress: bool) !void {
        try self.archive_queue.append(self.allocator, .{
            .source = try allocator.dupe(u8, source),
            .destination = try allocator.dupe(u8, destination),
            .compress = compress,
        });
    }

    fn queueDelete(self: *ActionContext, allocator: std.mem.Allocator, file_path: []const u8) !void {
        try self.delete_queue.append(self.allocator, try allocator.dupe(u8, file_path));
    }
};

/// A single rule with trigger, matchers, conditions, and actions
pub const Rule = struct {
    name: []const u8,
    trigger: Trigger,
    matcher: Matcher,
    conditions: []Condition,
    actions: []Action,
    priority: u8 = 50, // 0-100, higher = runs first
    enabled: bool = true,
    rate_limit: ?RateLimit = null,

    pub fn matches(self: *const Rule, file_path: []const u8, file_size: u64, file_mtime: i128) bool {
        if (!self.enabled) return false;

        // Check matcher
        if (!self.matcher.matches(file_path)) return false;

        // Check all conditions
        for (self.conditions) |*condition| {
            if (!condition.evaluate(file_path, file_size, file_mtime)) return false;
        }

        return true;
    }

    pub fn execute(self: *const Rule, allocator: std.mem.Allocator, file_path: []const u8, context: *ActionContext) !void {
        for (self.actions) |*action| {
            try action.execute(allocator, file_path, context);
        }
    }
};

/// Rate limiting configuration for rules
pub const RateLimit = struct {
    max_executions: u32, // Maximum number of executions
    time_window_secs: u64, // Time window in seconds
    current_count: u32 = 0,
    window_start: i64 = 0,

    pub fn canExecute(self: *RateLimit) bool {
        const now = std.time.timestamp();

        // Check if we need to reset the window
        if (now - self.window_start >= @as(i64, @intCast(self.time_window_secs))) {
            self.window_start = now;
            self.current_count = 0;
        }

        return self.current_count < self.max_executions;
    }

    pub fn recordExecution(self: *RateLimit) void {
        self.current_count += 1;
    }
};

/// Rule engine manages and evaluates rules
pub const RuleEngine = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayListUnmanaged(Rule),

    pub fn init(allocator: std.mem.Allocator) RuleEngine {
        return .{
            .allocator = allocator,
            .rules = std.ArrayListUnmanaged(Rule){},
        };
    }

    pub fn deinit(self: *RuleEngine) void {
        for (self.rules.items) |*rule| {
            self.allocator.free(rule.name);
            self.allocator.free(rule.conditions);
            self.allocator.free(rule.actions);
            if (rule.matcher.pattern) |p| self.allocator.free(p);
            if (rule.matcher.path_contains) |p| self.allocator.free(p);
            if (rule.matcher.extension) |e| self.allocator.free(e);
        }
        self.rules.deinit(self.allocator);
    }

    pub fn addRule(self: *RuleEngine, rule: Rule) !void {
        try self.rules.append(self.allocator, rule);
        // Sort by priority (higher first)
        std.mem.sort(Rule, self.rules.items, {}, compareRulePriority);
    }

    pub fn processFile(
        self: *RuleEngine,
        file_path: []const u8,
        file_size: u64,
        file_mtime: i128,
        trigger: Trigger,
        context: *ActionContext,
    ) !u32 {
        var matched_count: u32 = 0;

        for (self.rules.items) |*rule| {
            // Check if trigger matches
            if (rule.trigger != trigger) continue;

            // Check rate limit
            if (rule.rate_limit) |*limit| {
                if (!limit.canExecute()) {
                    continue;
                }
            }

            // Check if rule matches
            if (rule.matches(file_path, file_size, file_mtime)) {
                // Execute rule actions
                try rule.execute(self.allocator, file_path, context);
                matched_count += 1;

                // Update rate limit
                if (rule.rate_limit) |*limit| {
                    limit.recordExecution();
                }
            }
        }

        return matched_count;
    }

    pub fn validateRules(self: *RuleEngine) ![]const u8 {
        var issues = std.ArrayListUnmanaged(u8){};
        defer issues.deinit(self.allocator);
        const writer = issues.writer(self.allocator);

        for (self.rules.items, 0..) |*rule, index| {
            // Check rule name
            if (rule.name.len == 0) {
                try writer.print("Rule {d}: Name cannot be empty\n", .{index});
            }

            // Check priority range
            if (rule.priority > 100) {
                try writer.print("Rule '{s}': Priority must be 0-100\n", .{rule.name});
            }

            // Check actions
            if (rule.actions.len == 0) {
                try writer.print("Rule '{s}': Must have at least one action\n", .{rule.name});
            }
        }

        return try issues.toOwnedSlice(self.allocator);
    }
};

fn compareRulePriority(_: void, a: Rule, b: Rule) bool {
    return a.priority > b.priority;
}

/// Parse size string like "100KB", "5MB", "1GB"
pub fn parseSize(size_str: []const u8) !u64 {
    if (size_str.len < 2) return error.InvalidSize;

    var num_end: usize = 0;
    while (num_end < size_str.len and size_str[num_end] >= '0' and size_str[num_end] <= '9') {
        num_end += 1;
    }

    if (num_end == 0) return error.InvalidSize;

    const num = try std.fmt.parseInt(u64, size_str[0..num_end], 10);
    const unit = size_str[num_end..];

    const multiplier: u64 = if (std.ascii.eqlIgnoreCase(unit, "B"))
        1
    else if (std.ascii.eqlIgnoreCase(unit, "KB"))
        1024
    else if (std.ascii.eqlIgnoreCase(unit, "MB"))
        1024 * 1024
    else if (std.ascii.eqlIgnoreCase(unit, "GB"))
        1024 * 1024 * 1024
    else
        return error.InvalidSizeUnit;

    return num * multiplier;
}

/// Parse time range like "09:00-17:00"
pub fn parseTimeRange(time_str: []const u8) !struct { start_hour: u8, start_min: u8, end_hour: u8, end_min: u8 } {
    const dash_pos = std.mem.indexOf(u8, time_str, "-") orelse return error.InvalidTimeFormat;

    const start_str = time_str[0..dash_pos];
    const end_str = time_str[dash_pos + 1 ..];

    const start_colon = std.mem.indexOf(u8, start_str, ":") orelse return error.InvalidTimeFormat;
    const end_colon = std.mem.indexOf(u8, end_str, ":") orelse return error.InvalidTimeFormat;

    const start_hour = try std.fmt.parseInt(u8, start_str[0..start_colon], 10);
    const start_min = try std.fmt.parseInt(u8, start_str[start_colon + 1 ..], 10);
    const end_hour = try std.fmt.parseInt(u8, end_str[0..end_colon], 10);
    const end_min = try std.fmt.parseInt(u8, end_str[end_colon + 1 ..], 10);

    if (start_hour >= 24 or end_hour >= 24 or start_min >= 60 or end_min >= 60) {
        return error.InvalidTimeRange;
    }

    return .{
        .start_hour = start_hour,
        .start_min = start_min,
        .end_hour = end_hour,
        .end_min = end_min,
    };
}

/// Load rules from JSON file
pub fn loadRulesFromFile(allocator: std.mem.Allocator, file_path: []const u8) !RuleEngine {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(file_content);

    var engine = RuleEngine.init(allocator);
    errdefer engine.deinit();

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidRulesFormat;

    const rules_array = root.object.get("rules") orelse return error.MissingRulesArray;
    if (rules_array != .array) return error.InvalidRulesFormat;

    for (rules_array.array.items) |rule_value| {
        if (rule_value != .object) continue;
        const rule_obj = rule_value.object;

        // Parse rule name
        const name = rule_obj.get("name") orelse continue;
        if (name != .string) continue;

        // Parse trigger
        const trigger_value = rule_obj.get("trigger") orelse continue;
        if (trigger_value != .string) continue;
        const trigger = Trigger.fromString(trigger_value.string) orelse continue;

        // Parse matcher (optional)
        var matcher = Matcher{};
        if (rule_obj.get("match")) |match_obj| {
            if (match_obj == .object) {
                if (match_obj.object.get("pattern")) |p| {
                    if (p == .string) {
                        matcher.pattern = try allocator.dupe(u8, p.string);
                    }
                }
                if (match_obj.object.get("path_contains")) |p| {
                    if (p == .string) {
                        matcher.path_contains = try allocator.dupe(u8, p.string);
                    }
                }
                if (match_obj.object.get("extension")) |e| {
                    if (e == .string) {
                        matcher.extension = try allocator.dupe(u8, e.string);
                    }
                }
            }
        }

        // Parse conditions (optional)
        var conditions = std.ArrayListUnmanaged(Condition){};
        defer conditions.deinit(allocator);

        if (rule_obj.get("conditions")) |conds_array| {
            if (conds_array == .array) {
                for (conds_array.array.items) |cond_value| {
                    if (cond_value != .object) continue;
                    const cond_obj = cond_value.object;

                    if (cond_obj.get("size_gt")) |val| {
                        if (val == .string) {
                            const size = try parseSize(val.string);
                            try conditions.append(allocator, .{ .size_gt = size });
                        }
                    } else if (cond_obj.get("size_lt")) |val| {
                        if (val == .string) {
                            const size = try parseSize(val.string);
                            try conditions.append(allocator, .{ .size_lt = size });
                        }
                    } else if (cond_obj.get("time_of_day")) |val| {
                        if (val == .string) {
                            const time_range = try parseTimeRange(val.string);
                            try conditions.append(allocator, .{
                                .time_of_day = .{
                                    .start_hour = time_range.start_hour,
                                    .start_min = time_range.start_min,
                                    .end_hour = time_range.end_hour,
                                    .end_min = time_range.end_min,
                                },
                            });
                        }
                    }
                }
            }
        }

        // Parse actions
        var actions = std.ArrayListUnmanaged(Action){};
        defer actions.deinit(allocator);

        if (rule_obj.get("actions")) |actions_array| {
            if (actions_array == .array) {
                for (actions_array.array.items) |action_value| {
                    if (action_value != .object) continue;
                    const action_obj = action_value.object;

                    if (action_obj.get("organize")) |_| {
                        try actions.append(allocator, .{ .organize = .{
                            .by_category = true,
                            .by_date = false,
                            .by_size = false,
                        } });
                    } else if (action_obj.get("move")) |move_obj| {
                        if (move_obj == .object) {
                            if (move_obj.object.get("destination")) |dest| {
                                if (dest == .string) {
                                    try actions.append(allocator, .{ .move = .{
                                        .destination = try allocator.dupe(u8, dest.string),
                                    } });
                                }
                            }
                        }
                    } else if (action_obj.get("log")) |log_obj| {
                        if (log_obj == .object) {
                            if (log_obj.object.get("message")) |msg| {
                                if (msg == .string) {
                                    try actions.append(allocator, .{ .log = .{
                                        .message = try allocator.dupe(u8, msg.string),
                                    } });
                                }
                            }
                        }
                    }
                }
            }
        }

        // Parse priority (optional, default 50)
        var priority: u8 = 50;
        if (rule_obj.get("priority")) |p| {
            if (p == .integer) {
                priority = @intCast(@min(100, @max(0, p.integer)));
            }
        }

        // Create rule
        const rule = Rule{
            .name = try allocator.dupe(u8, name.string),
            .trigger = trigger,
            .matcher = matcher,
            .conditions = try conditions.toOwnedSlice(allocator),
            .actions = try actions.toOwnedSlice(allocator),
            .priority = priority,
        };

        try engine.addRule(rule);
    }

    return engine;
}
