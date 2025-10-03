const std = @import("std");
const testing = std.testing;
const watch_rules = @import("watch_rules.zig");

const Trigger = watch_rules.Trigger;
const Matcher = watch_rules.Matcher;
const Condition = watch_rules.Condition;
const Action = watch_rules.Action;
const Rule = watch_rules.Rule;
const RuleEngine = watch_rules.RuleEngine;
const ActionContext = watch_rules.ActionContext;

test "Trigger - fromString and toString" {
    try testing.expectEqual(Trigger.file_created, Trigger.fromString("file_created").?);
    try testing.expectEqual(Trigger.file_modified, Trigger.fromString("file_modified").?);
    try testing.expectEqual(Trigger.file_deleted, Trigger.fromString("file_deleted").?);
    try testing.expectEqual(Trigger.periodic, Trigger.fromString("periodic").?);
    try testing.expectEqual(@as(?Trigger, null), Trigger.fromString("invalid"));

    try testing.expectEqualStrings("file_created", Trigger.file_created.toString());
    try testing.expectEqualStrings("file_modified", Trigger.file_modified.toString());
}

test "Matcher - glob pattern matching" {
    const matcher = Matcher{ .pattern = "*.pdf" };

    try testing.expect(matcher.matches("document.pdf"));
    try testing.expect(matcher.matches("report.pdf"));
    try testing.expect(!matcher.matches("document.txt"));
    try testing.expect(!matcher.matches("pdf"));
}

test "Matcher - path contains" {
    const matcher = Matcher{ .path_contains = "work" };

    try testing.expect(matcher.matches("/home/user/work/document.pdf"));
    try testing.expect(matcher.matches("/work/files/doc.txt"));
    try testing.expect(!matcher.matches("/home/personal/doc.pdf"));
}

test "Matcher - extension matching" {
    const matcher = Matcher{ .extension = ".pdf" };

    try testing.expect(matcher.matches("document.pdf"));
    try testing.expect(matcher.matches("/path/to/file.pdf"));
    try testing.expect(matcher.matches("file.PDF")); // Case insensitive
    try testing.expect(!matcher.matches("document.txt"));
}

test "Matcher - combined matchers" {
    const matcher = Matcher{
        .pattern = "*.pdf",
        .path_contains = "work",
    };

    try testing.expect(matcher.matches("/home/work/document.pdf"));
    try testing.expect(!matcher.matches("/home/work/document.txt")); // Wrong extension
    try testing.expect(!matcher.matches("/home/personal/document.pdf")); // Wrong path
}

test "Condition - size_gt" {
    const condition = Condition{ .size_gt = 1024 };

    try testing.expect(condition.evaluate("test.txt", 2048, 0));
    try testing.expect(!condition.evaluate("test.txt", 512, 0));
}

test "Condition - size_lt" {
    const condition = Condition{ .size_lt = 1024 };

    try testing.expect(condition.evaluate("test.txt", 512, 0));
    try testing.expect(!condition.evaluate("test.txt", 2048, 0));
}

test "ActionContext - queue operations" {
    const allocator = testing.allocator;

    var context = ActionContext.init(allocator);
    defer context.deinit();

    const action_organize = Action{ .organize = .{ .by_category = true } };
    try action_organize.execute(allocator, "/test/file.pdf", &context);

    try testing.expectEqual(@as(usize, 1), context.organize_queue.items.len);
}

test "Rule - basic matching" {
    const allocator = testing.allocator;

    const conditions = try allocator.alloc(Condition, 1);
    defer allocator.free(conditions);
    conditions[0] = .{ .size_gt = 1024 };

    const actions = try allocator.alloc(Action, 1);
    defer allocator.free(actions);
    actions[0] = .{ .organize = .{ .by_category = true } };

    const rule = Rule{
        .name = "Test Rule",
        .trigger = .file_created,
        .matcher = .{ .pattern = "*.pdf" },
        .conditions = conditions,
        .actions = actions,
        .priority = 50,
    };

    try testing.expect(rule.matches("document.pdf", 2048, 0));
    try testing.expect(!rule.matches("document.pdf", 512, 0)); // Size too small
    try testing.expect(!rule.matches("document.txt", 2048, 0)); // Wrong extension
}

test "Rule - priority ordering" {
    const allocator = testing.allocator;

    var engine = RuleEngine.init(allocator);
    defer engine.deinit();

    const rule1 = Rule{
        .name = try allocator.dupe(u8, "Low Priority"),
        .trigger = .file_created,
        .matcher = .{},
        .conditions = &[_]Condition{},
        .actions = &[_]Action{},
        .priority = 10,
    };

    const rule2 = Rule{
        .name = try allocator.dupe(u8, "High Priority"),
        .trigger = .file_created,
        .matcher = .{},
        .conditions = &[_]Condition{},
        .actions = &[_]Action{},
        .priority = 90,
    };

    try engine.addRule(rule1);
    try engine.addRule(rule2);

    // Higher priority should come first
    try testing.expectEqual(@as(u8, 90), engine.rules.items[0].priority);
    try testing.expectEqual(@as(u8, 10), engine.rules.items[1].priority);
}

test "parseSize - various formats" {
    try testing.expectEqual(@as(u64, 100), try watch_rules.parseSize("100B"));
    try testing.expectEqual(@as(u64, 1024), try watch_rules.parseSize("1KB"));
    try testing.expectEqual(@as(u64, 1024 * 1024), try watch_rules.parseSize("1MB"));
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024), try watch_rules.parseSize("1GB"));
    try testing.expectEqual(@as(u64, 512 * 1024), try watch_rules.parseSize("512KB"));
}

test "parseTimeRange - valid format" {
    const time_range = try watch_rules.parseTimeRange("09:00-17:00");

    try testing.expectEqual(@as(u8, 9), time_range.start_hour);
    try testing.expectEqual(@as(u8, 0), time_range.start_min);
    try testing.expectEqual(@as(u8, 17), time_range.end_hour);
    try testing.expectEqual(@as(u8, 0), time_range.end_min);
}

test "parseTimeRange - with minutes" {
    const time_range = try watch_rules.parseTimeRange("09:30-17:45");

    try testing.expectEqual(@as(u8, 9), time_range.start_hour);
    try testing.expectEqual(@as(u8, 30), time_range.start_min);
    try testing.expectEqual(@as(u8, 17), time_range.end_hour);
    try testing.expectEqual(@as(u8, 45), time_range.end_min);
}

test "glob matching - asterisk" {
    const pattern = "*.txt";
    try testing.expect(watch_rules.matchGlob(pattern, "file.txt"));
    try testing.expect(watch_rules.matchGlob(pattern, "document.txt"));
    try testing.expect(!watch_rules.matchGlob(pattern, "file.pdf"));
}

test "glob matching - question mark" {
    const pattern = "file?.txt";
    try testing.expect(watch_rules.matchGlob(pattern, "file1.txt"));
    try testing.expect(watch_rules.matchGlob(pattern, "fileA.txt"));
    try testing.expect(!watch_rules.matchGlob(pattern, "file.txt"));
    try testing.expect(!watch_rules.matchGlob(pattern, "file12.txt"));
}

test "glob matching - complex patterns" {
    try testing.expect(watch_rules.matchGlob("doc*.pdf", "document.pdf"));
    try testing.expect(watch_rules.matchGlob("doc*.pdf", "doc123.pdf"));
    try testing.expect(watch_rules.matchGlob("*work*.txt", "homework.txt"));
    try testing.expect(watch_rules.matchGlob("*work*.txt", "work_file.txt"));
    try testing.expect(!watch_rules.matchGlob("*work*.txt", "file.txt"));
}

test "RateLimit - basic functionality" {
    var rate_limit = watch_rules.RateLimit{
        .max_executions = 3,
        .time_window_secs = 60,
    };

    // Should allow first 3 executions
    try testing.expect(rate_limit.canExecute());
    rate_limit.recordExecution();

    try testing.expect(rate_limit.canExecute());
    rate_limit.recordExecution();

    try testing.expect(rate_limit.canExecute());
    rate_limit.recordExecution();

    // Fourth execution should be blocked
    try testing.expect(!rate_limit.canExecute());
}

test "RuleEngine - validate rules" {
    const allocator = testing.allocator;

    var engine = RuleEngine.init(allocator);
    defer engine.deinit();

    // Add rule with empty name (should fail validation)
    const invalid_rule = Rule{
        .name = try allocator.dupe(u8, ""),
        .trigger = .file_created,
        .matcher = .{},
        .conditions = &[_]Condition{},
        .actions = &[_]Action{},
    };

    try engine.addRule(invalid_rule);

    const validation_result = try engine.validateRules();
    defer allocator.free(validation_result);

    try testing.expect(validation_result.len > 0);
    try testing.expect(std.mem.indexOf(u8, validation_result, "Name cannot be empty") != null);
}
