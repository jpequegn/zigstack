# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZigStack is a file organization CLI tool written in Zig. It categorizes files by extension, provides organization previews, and can actually organize files with advanced options including date-based organization, size-based separation, duplicate detection, and recursive processing.

## Core Architecture

### Modular Architecture (Phase 1)
- **Entry Point**: `src/main.zig` - Main application entry and CLI
- **Core Modules**: `src/core/` - File info, config, organization, tracking, utilities
- **Commands**: `src/commands/` - Command system with organize, future commands
- **Test Helpers**: `src/test_helpers.zig` - Reusable test utilities and scenarios
- **Build Configuration**: `build.zig` - Multi-target build with separate test runners

### Key Data Structures

**File Management**:
- `FileInfo`: Extended with `size`, `created_time`, `modified_time`, `hash` for advanced features
- `FileCategory`: Enum with 9 categories (Documents, Images, Videos, Audio, Archives, Code, Data, Configuration, Other)
- `OrganizationPlan`: HashMap for categories, StringHashMap for date/size-based directory structures

**Configuration**:
- `Config`: CLI flags including date/size/duplicate/recursive options
- `ConfigData`: JSON-based custom category definitions
- `DateFormat`: year, year_month, year_month_day
- `DuplicateAction`: skip, rename, replace, keep_both

**Safety**:
- `MoveTracker`: Records all file moves for rollback capability
- `MoveRecord`: Original and destination paths for each move

### Core Function Groups

**File Analysis**:
- `getFileExtension()`: Handles regular files, hidden files, no-extension cases
- `categorizeFileByExtension()`: Maps extensions to categories (case-insensitive)
- `getFileStats()`: Retrieves size, timestamps from filesystem
- `calculateFileHash()`: SHA-256 hashing for duplicate detection

**Organization Logic**:
- `listFiles()`: Main directory traversal and categorization
- `formatDatePath()`: Converts timestamps to date-based paths (year/month/day)
- `organizeBySizeAndCategory()`: Separates large files from regular files
- `detectDuplicates()`: SHA-256 based duplicate detection with configurable actions

**Operations**:
- `createDirectories()`: Creates category folders with conflict handling
- `moveFiles()`: Moves files with rollback support on errors
- `resolveFilenameConflict()`: Auto-renames conflicting files (file_1.txt, file_2.txt, etc.)

## Development Commands

### Build and Run
```bash
# Build the project
zig build

# Run with preview mode (default, no changes)
zig build run -- /path/to/analyze

# Run with file operations
zig build run -- --move /path/to/organize

# Build directly and run
./zig-out/bin/zigstack --move /tmp/test
```

### Testing

The build system supports multiple test targets for focused testing:

```bash
# Run all tests (unit + integration)
zig build test

# Run only unit tests (core modules and commands)
zig build test-unit

# Run only integration tests (backward compatibility, workflows)
zig build test-integration

# List all available build targets
zig build --help
```

**Test Organization**:
- **Unit Tests**: Focus on individual functions and modules
  - `src/core/utils_test.zig` - Core utility functions
  - `src/commands/command_test.zig` - Command parsing and routing
- **Integration Tests**: Test multi-module workflows
  - `src/commands/backward_compat_test.zig` - Backward compatibility scenarios
- **Test Helpers**: `src/test_helpers.zig` provides reusable test utilities:
  - `TestScenario` - Managed temporary test directories
  - `createTestFile()` - File creation helpers
  - `verifyFileMoved()` - Operation verification
  - `countFilesInDir()` - Directory analysis

**Using Test Helpers**:
```zig
const helpers = @import("test_helpers.zig");

test "my test" {
    var scenario = try helpers.TestScenario.init(allocator);
    defer scenario.deinit();

    try scenario.createFile("test.txt", "content");
    // Test operations...
}
```

### Development Workflow
```bash
# Quick compile check
zig build

# Test-driven development with focused testing
zig build test-unit && zig build test-integration

# Full test suite
zig build test

# Run application
zig build run -- /tmp/test

# Test advanced features
zig build run -- --by-date --by-size --detect-dups --recursive --verbose --move /tmp/test
```

## CLI Interface

### Basic Usage
`zigstack [OPTIONS] <directory>`

### Key Options
- `-d/--dry-run`: Preview mode (default)
- `-m/--move`: Create directories and move files
- `--by-date --date-format [year|year-month|year-month-day]`: Organize by date
- `--by-size --size-threshold MB`: Separate large files
- `--detect-dups --dup-action [skip|rename|replace|keep-both]`: Handle duplicates
- `--recursive --max-depth N`: Process subdirectories
- `-V/--verbose`: Detailed logging

### Operation Modes
1. **Preview** (default): Shows planned organization without changes
2. **Create** (`--create`): Creates category directories only
3. **Move** (`--move`): Full organization with file moving

## Testing Strategy

Comprehensive test coverage with modular organization:

### Build System Test Targets

The build system provides three test execution modes:

1. **`zig build test`** - All tests (unit + integration)
   - Runs complete test suite
   - Uses `src/main.zig` as root module for all imports

2. **`zig build test-unit`** - Unit tests only
   - Filters: `core/utils_test`, `commands/command_test`
   - Fast execution for TDD workflows
   - Tests individual functions and modules

3. **`zig build test-integration`** - Integration tests only
   - Filters: `commands/backward_compat_test`
   - Tests multi-module workflows and scenarios
   - Verifies system behavior end-to-end

### Test Coverage

**Unit Tests** (`test-unit`):
- Extension extraction and categorization
- Date format parsing and path generation
- Hash calculation and duplicate detection
- Config parsing and validation
- Command parsing and routing

**Integration Tests** (`test-integration`):
- Directory creation workflows
- File moving with conflict resolution
- Rollback functionality on errors
- Empty directory and special character handling
- Backward compatibility with legacy CLI

**Edge Case Coverage**:
- Empty filenames, very long extensions
- Invalid characters, hidden files
- Boundary conditions (no extension, dots in names)
- Date edge cases (leap years, timezones)
- Large files and memory-efficient hashing

### Test Helper Utilities

`src/test_helpers.zig` provides reusable test infrastructure:

**Core Functions**:
- `createTempTestDir()` - Create unique temporary directories
- `removeTempTestDir()` - Clean up test directories
- `createTestFile()` - Create files with content
- `createTestFilesWithExtensions()` - Batch file creation
- `createTestDirStructure()` - Create directory hierarchies
- `countFilesInDir()` - Count files with optional extension filter
- `fileExistsInDir()` - Check file existence
- `createTestFileWithSize()` - Create files of specific sizes
- `verifyFileMoved()` - Verify file move operations

**TestScenario Builder**:
```zig
var scenario = try TestScenario.init(allocator);
defer scenario.deinit();  // Automatic cleanup

try scenario.createFile("test.txt", "content");
try scenario.createFiles(&[_][]const u8{".jpg", ".png"});
try scenario.createSubdir("Documents");
```

### Adding New Tests

1. Create test file in appropriate module directory
2. Add test block with `_ = @import("path/to/test.zig");` in `src/main.zig`
3. Use test helpers for setup/teardown
4. Update build.zig filters if creating new test category

## Memory Management

Critical memory patterns in this codebase:

**Allocator Usage**:
- GeneralPurposeAllocator for main operations
- ArenaAllocator for temporary test data
- Careful cleanup in defer blocks

**String Handling**:
- All FileInfo strings are duped and must be freed
- Path buffers use std.fs.MAX_PATH_BYTES (4096)
- Config data cleanup via ConfigData.deinit()

**HashMap Management**:
- OrganizationPlan uses both typed HashMap and StringHashMap
- Each ArrayList in maps requires separate deinit
- Proper iteration and cleanup in nested structures

**Rollback Safety**:
- MoveTracker dupes all paths to preserve state
- Reverse-order rollback on any move failure
- All recorded moves freed in MoveTracker.deinit()