# Phase 1: Foundation - GitHub Issues

## Issue #10: Refactor Core Functionality into Modules

**Title**: Refactor core functionality into modular structure

**Description**:
Break down the monolithic `src/main.zig` into logical modules to support subcommand architecture.

**Tasks**:
- [ ] Create `src/core/` directory structure
- [ ] Extract FileInfo, FileCategory into `src/core/file_info.zig`
- [ ] Extract OrganizationPlan and categorization logic into `src/core/organization.zig`
- [ ] Extract Config, ConfigData into `src/core/config.zig`
- [ ] Extract MoveTracker, MoveRecord into `src/core/tracker.zig`
- [ ] Update imports in main.zig
- [ ] Ensure all existing tests still pass
- [ ] Run `zig build test` to verify no regressions

**Acceptance Criteria**:
- All core data structures moved to dedicated modules
- Zero test failures
- Build completes successfully
- Code organization follows Zig best practices

**Estimated Effort**: 4-6 hours

**Dependencies**: None

**Labels**: refactoring, foundation, breaking-change-potential

---

## Issue #11: Create Command Infrastructure

**Title**: Implement command routing and dispatch system

**Description**:
Create the infrastructure to support multiple subcommands with shared functionality.

**Tasks**:
- [ ] Create `src/commands/` directory
- [ ] Define `Command` interface/protocol in `src/commands/command.zig`
- [ ] Implement command registry system
- [ ] Create command parser that detects subcommands
- [ ] Add fallback to default "organize" command for backward compatibility
- [ ] Implement shared option parsing (--verbose, --dry-run, etc.)
- [ ] Create help system that displays available commands
- [ ] Write unit tests for command routing

**Command Interface**:
```zig
const Command = struct {
    name: []const u8,
    description: []const u8,
    fn execute(allocator: std.mem.Allocator, args: []const []const u8, config: *Config) !void;
    fn printHelp() void;
};
```

**Acceptance Criteria**:
- Command routing works correctly
- Help text shows all available commands
- Unknown commands show helpful error messages
- Backward compatibility maintained (direct path argument works)
- Tests verify command dispatch logic

**Estimated Effort**: 6-8 hours

**Dependencies**: Issue #10

**Labels**: foundation, architecture, enhancement

---

## Issue #12: Implement Backward Compatibility Layer

**Title**: Ensure existing CLI usage patterns continue to work

**Description**:
Maintain full backward compatibility with v0.2.0 CLI interface while introducing subcommands.

**Tasks**:
- [ ] Detect if first argument is a command or path
- [ ] If path, default to "organize" command
- [ ] Ensure all existing flags work with implicit "organize"
- [ ] Add tests for backward compatibility scenarios
- [ ] Document migration path in README
- [ ] Create compatibility test suite

**Test Scenarios**:
```bash
# All these should continue working:
zigstack /path/to/dir
zigstack --move /path/to/dir
zigstack --by-date --move /path
zigstack --verbose --dry-run /path
```

**Acceptance Criteria**:
- All v0.2.0 usage patterns work without changes
- No breaking changes for existing users
- Comprehensive test coverage for backward compatibility
- Migration guide documented

**Estimated Effort**: 3-4 hours

**Dependencies**: Issue #11

**Labels**: backward-compatibility, testing, documentation

---

## Issue #13: Create Shared Utilities Module

**Title**: Extract common functionality into shared utilities

**Description**:
Centralize common functionality used across multiple commands (output formatting, path handling, error reporting).

**Tasks**:
- [ ] Create `src/core/utils.zig`
- [ ] Extract output formatting functions (printSuccess, printError, printInfo)
- [ ] Extract path utilities (resolvePath, validatePath, joinPath)
- [ ] Extract file utilities (getFileSize, getFileStats, etc.)
- [ ] Create consistent error handling patterns
- [ ] Add color support for terminal output (optional)
- [ ] Write unit tests for utilities

**Utility Functions**:
- Output: `printSuccess()`, `printError()`, `printWarning()`, `printInfo()`
- Paths: `resolvePath()`, `validatePath()`, `joinPath()`, `normalizePath()`
- Files: `fileExists()`, `isDirectory()`, `getFileSize()`, `getFileHash()`
- Format: `formatBytes()`, `formatDuration()`, `formatPercentage()`

**Acceptance Criteria**:
- All common functions extracted and tested
- Commands use shared utilities consistently
- Error messages follow consistent format
- Unit tests achieve >90% coverage

**Estimated Effort**: 4-5 hours

**Dependencies**: Issue #10

**Labels**: refactoring, utilities, enhancement

---

## Issue #14: Update Build System and Tests

**Title**: Adapt build.zig for modular architecture

**Description**:
Update the build system to handle the new modular structure and ensure comprehensive testing.

**Tasks**:
- [ ] Update `build.zig` to compile new module structure
- [ ] Ensure all modules are included in test compilation
- [ ] Add integration test target separate from unit tests
- [ ] Create test helper utilities for common test scenarios
- [ ] Set up test coverage reporting (if possible with Zig)
- [ ] Update CI/CD configuration (if exists)
- [ ] Document testing procedures in CLAUDE.md

**Test Targets**:
```bash
zig build test               # All tests
zig build test-unit          # Unit tests only
zig build test-integration   # Integration tests only
zig build test-commands      # Command-specific tests
```

**Acceptance Criteria**:
- Build system supports modular architecture
- All tests can be run individually or together
- Test output is clear and actionable
- Build time doesn't increase significantly
- Documentation reflects new test structure

**Estimated Effort**: 3-4 hours

**Dependencies**: Issues #10, #11, #13

**Labels**: build-system, testing, infrastructure

---

## Phase 1 Summary

**Total Estimated Effort**: 20-27 hours
**Total Issues**: 5 (including foundation issue #10-14)

**Critical Path**:
1. Issue #10 (Refactor core) - Must complete first
2. Issue #11 (Command infrastructure) - Depends on #10
3. Issues #12, #13 can proceed in parallel after #11
4. Issue #14 (Build system) - Final integration

**Risk Assessment**:
- **Medium Risk**: Large refactoring may introduce subtle bugs
- **Mitigation**: Comprehensive test coverage, incremental changes
- **Backward Compatibility**: Critical - must be verified at each step
