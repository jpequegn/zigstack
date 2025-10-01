# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZigStack is a file organization CLI tool written in Zig. It categorizes files by extension, provides organization previews, and can actually organize files with advanced options including date-based organization, size-based separation, duplicate detection, and recursive processing.

## Core Architecture

### Single-Module Design
- **Entry Point**: `src/main.zig` - Complete application logic (~2500 lines)
- **Build Configuration**: `build.zig` - Standard Zig build with test support

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
```bash
# Run all tests (unit + integration + edge cases)
zig build test

# Run specific test with timeout for long-running tests
timeout 10 zig build run -- /tmp/test_dir
```

### Development Workflow
```bash
# Quick compile check
zig build

# Test-driven development
zig build test && zig build run -- /tmp

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

Comprehensive test coverage across three levels:

**Unit Tests**:
- Extension extraction and categorization
- Date format parsing and path generation
- Hash calculation and duplicate detection
- Config parsing and validation

**Integration Tests**:
- Directory creation workflows
- File moving with conflict resolution
- Rollback functionality on errors
- Empty directory and special character handling

**Edge Case Tests**:
- Empty filenames, very long extensions
- Invalid characters, hidden files
- Boundary conditions (no extension, dots in names)
- Date edge cases (leap years, timezones)
- Large files and memory-efficient hashing

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