# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZigStack is a file organization and analysis CLI tool written in Zig. It analyzes directory contents, categorizes files by extension, and provides organization previews showing how files would be grouped by type (Documents, Images, Videos, Audio, Archives, Code, Data, Configuration, Other).

## Core Architecture

### Single-Module Structure
- **Entry Point**: `src/main.zig` - Contains the complete application logic
- **Build Configuration**: `build.zig` - Standard Zig build configuration with test support

### Key Components

**Data Structures**:
- `FileCategory`: Enum defining file categories with string conversion
- `FileInfo`: File metadata (name, extension, category)
- `OrganizationPlan`: HashMap-based structure grouping files by category

**Core Functions**:
- `categorizeFileByExtension()`: Extension-to-category mapping with case-insensitive matching
- `getFileExtension()`: Extracts file extensions, handles edge cases (hidden files, no extension)
- `listFiles()`: Main analysis logic - directory traversal, categorization, memory management
- `validateDirectory()`: Directory existence and permissions validation

**File Categorization Logic**:
The application categorizes files into predefined categories based on extension patterns:
- Documents: .txt, .pdf, .md, .doc, .docx, .odt, .rtf, .tex
- Images: .jpg, .jpeg, .png, .gif, .bmp, .svg, .ico, .webp
- Code: .zig, .c, .cpp, .py, .js, .ts, .java, .cs, .go, .rs, .sh, .bat
- And more categories for videos, audio, archives, data, and configuration files

## Development Commands

### Build and Run
```bash
# Build the project
zig build

# Run with arguments
zig build run -- /path/to/analyze

# Build and run directly
./zig-out/bin/zigstack /path/to/analyze
```

### Testing
```bash
# Run all tests
zig build test

# Run tests with verbose output
zig build test -- --verbose
```

### Development Workflow
```bash
# Quick iteration cycle
zig build run -- . && echo "Build successful"

# Test-driven development
zig build test && zig build run -- /tmp
```

## CLI Interface

**Basic Usage**: `zigstack <directory>`
**Options**: `-h/--help`, `-v/--version`

The tool validates directory access, analyzes files, and outputs:
- Total file count
- Files grouped by category with icons
- Organization summary with percentages
- File extension breakdown
- Note that it's preview-only (no files are moved)

## Testing Strategy

The codebase includes comprehensive unit tests for core functions:
- `getFileExtension()`: Tests regular files, hidden files, files without extensions
- `categorizeFileByExtension()`: Tests all category mappings, case insensitivity, unknown extensions

## Memory Management

Uses Zig's GeneralPurposeAllocator with proper cleanup:
- String duplication for file names and extensions
- HashMap cleanup for categorization data
- Extension counting with proper memory deallocation