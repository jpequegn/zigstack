# Changelog

All notable changes to ZigStack will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2024-10-04

### Added

#### Six Powerful Commands
- **analyze command**: Disk usage analysis with detailed breakdowns and visualization
  - Content metadata analysis for images, videos, and documents
  - JSON export for analysis results
  - Top N largest files/directories filtering
  - Recursive directory scanning with depth control

- **dedupe command**: Interactive and automatic duplicate file management
  - SHA-256 based duplicate detection
  - Multiple resolution strategies (keep-oldest, keep-newest, keep-largest)
  - Hardlink support for space-saving without deletion
  - CSV and JSON export for duplicate reports
  - Interactive mode with user prompts

- **archive command**: Age-based file archiving with compression
  - Archive files older than specified duration (days, months, years)
  - tar.gz compression support with configurable compression levels
  - Preserve or flatten directory structure
  - Move or copy operations
  - Category and size filtering

- **watch command**: Directory monitoring with automatic organization
  - File system monitoring with configurable check intervals
  - Custom rules engine for advanced organization logic
  - Rule validation before running
  - Background daemon mode (planned)
  - Logging to file with configurable verbosity

- **workspace command**: Developer workspace management
  - Project type detection (Node.js, Python, Rust, Zig, Go, Java)
  - Build artifact and dependency cleanup
  - Multiple cleanup strategies (conservative, moderate, aggressive)
  - Inactive project detection
  - JSON export for workspace reports

#### Command Infrastructure
- **Command-based architecture**: Modular command system with registry and dispatch
- **100% backward compatibility**: All v0.2.0 CLI patterns continue to work unchanged
- **Subcommand routing**: Intelligent command detection and argument parsing
- **Extensible design**: Easy to add new commands in the future

#### Performance & Benchmarking
- **Performance benchmarking suite**: Comprehensive benchmarks for all operations
  - Extension extraction: 243M files/sec (2,430x target)
  - File categorization: 13M files/sec (263x target)
  - File scanning: 1.35M files/sec (1,351x target)
  - File stats: 351K files/sec (351x target)
  - Hash calculation: 30K files/sec (60x target)
- **Benchmark infrastructure**: `zig build benchmark` command
- **Performance documentation**: Detailed performance characteristics and optimization guides

#### Documentation
- **Complete documentation suite**:
  - Getting Started guide
  - Comprehensive FAQ (30+ questions)
  - Troubleshooting guide (50+ scenarios)
  - Command reference structure
  - Tutorial guides framework
  - Performance documentation
- **docs/ directory**: Organized documentation with clear navigation
- **Updated README.md**: All six commands documented with examples
- **CLAUDE.md updates**: Current architecture and command documentation

#### Testing
- **50+ tests**: Comprehensive test coverage for all commands
- **Test infrastructure**: Separate test targets (test, test-unit, test-integration)
- **Backward compatibility tests**: Ensure v0.2.0 patterns still work
- **Command-specific tests**: Individual test files for each command

### Changed

- **Modular architecture**: Refactored from monolithic to command-based structure
  - src/commands/ - Six command implementations
  - src/core/ - Shared core functionality
  - src/main.zig - Command routing and dispatch
- **Enhanced CLI**: Better help text and error messages
- **Improved organization logic**: More efficient file scanning and categorization
- **Better error handling**: More informative error messages and recovery

### Performance

- **Optimized file operations**: Buffered I/O and efficient directory iteration
- **Memory efficiency**: Typical usage <100MB for most operations
- **Fast categorization**: Optimized lookup tables and minimal branching
- **Streaming hash calculation**: Memory-efficient duplicate detection

### Documentation

- **100+ examples**: Covering all commands and use cases
- **Platform-specific guidance**: macOS, Linux, and Windows notes
- **Common workflows**: Daily, monthly, and developer maintenance tasks
- **Troubleshooting**: Comprehensive solutions for common issues

## [0.2.0] - 2024-09-XX

### Added

- **Date-based organization**: Organize files by creation/modification time
  - Three date formats: year, year-month, year-month-day
  - Configurable date path formatting

- **Size-based organization**: Separate large files from regular files
  - Customizable size threshold (default: 100MB)
  - Hierarchical organization with size categories

- **Duplicate file detection**: SHA-256 based duplicate detection
  - Multiple handling strategies (skip, rename, replace, keep-both)
  - Efficient hash calculation with streaming

- **Recursive directory processing**: Process subdirectories
  - Configurable maximum depth (default: 10)
  - Safe handling of symlinks and cycles

### Changed

- **Enhanced CLI**: 8 new command-line options
- **Improved performance**: Optimized file scanning and processing
- **Better error handling**: More informative error messages

### Fixed

- Various edge case handling improvements
- Memory leak fixes in recursive operations
- Proper handling of special characters in filenames

## [0.1.0] - 2024-09-XX

### Added

- **Basic file organization**: Categorize files by extension
  - 9 categories: Documents, Images, Videos, Audio, Archives, Code, Data, Configuration, Other
  - 50+ recognized file extensions

- **Directory operations**:
  - Preview mode (dry-run) as default
  - Create directories only mode
  - Move files mode

- **Custom configuration**: JSON-based configuration for custom categories
- **Conflict resolution**: Automatic file renaming when conflicts occur
- **Rollback support**: Automatic rollback on errors during file moves
- **Verbose logging**: Detailed operation tracking
- **Test suite**: Comprehensive unit tests for core functionality

### Initial Features

- File categorization by extension
- Directory creation and file moving
- Dry-run preview mode
- Custom configuration support
- Basic test suite

---

## Migration Guide

### From v0.2.0 to v0.3.0

**No migration required!** All v0.2.0 usage patterns continue to work:

```bash
# v0.2.0 style (still works)
zigstack /path/to/directory
zigstack --move /path/to/directory
zigstack --by-date --move /path

# v0.3.0 style (new, explicit command)
zigstack organize /path/to/directory
zigstack organize --move /path/to/directory
zigstack organize --by-date --move /path
```

**New features available:**
- Use `zigstack <command> --help` to explore new commands
- See docs/ directory for detailed documentation
- Run `zig build benchmark` to verify performance on your system

### From v0.1.0 to v0.3.0

All v0.1.0 features are preserved. New in v0.2.0 and v0.3.0:
- Date-based organization (`--by-date`)
- Size-based organization (`--by-size`)
- Duplicate detection (`--detect-dups`)
- Recursive processing (`--recursive`)
- Five new commands (analyze, dedupe, archive, watch, workspace)

## Known Issues

None currently reported. Please open an issue on GitHub if you encounter any problems.

## Future Releases

### Planned for v0.4.0
- Daemon mode for watch command
- Parallel processing for multi-core systems
- Additional project types for workspace command
- Enhanced content analysis for more file types

### Under Consideration
- GUI interface
- Cloud storage integration
- Scheduled organization tasks
- Machine learning-based categorization

---

## Links

- [GitHub Repository](https://github.com/jpequegn/zigstack)
- [Documentation](docs/)
- [Issue Tracker](https://github.com/jpequegn/zigstack/issues)
- [Release Notes](https://github.com/jpequegn/zigstack/releases)
