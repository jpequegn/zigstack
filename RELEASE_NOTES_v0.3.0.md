# ZigStack v0.3.0 Release Notes

**Release Date**: October 4, 2024

We're excited to announce ZigStack v0.3.0, a major release that transforms ZigStack from a simple file organizer into a comprehensive file management toolkit with six powerful commands!

## 🎉 What's New

### Six Powerful Commands

ZigStack v0.3.0 introduces **five new commands** alongside the enhanced organize command:

#### 1. **organize** - Smart File Organization (Enhanced)
Your familiar file organization command, now with improved performance and better integration.
```bash
zigstack organize --move ~/Downloads
```

#### 2. **analyze** - Disk Usage Analysis
Get detailed insights into your disk usage with visualization and content metadata.
```bash
zigstack analyze --content --top 20 ~/Documents
```
- Disk usage analysis with category breakdowns
- Content metadata for images, videos, and documents
- JSON export for further processing
- Find your largest files and space hogs

#### 3. **dedupe** - Duplicate File Management
Find and manage duplicate files with intelligent strategies.
```bash
zigstack dedupe --auto keep-newest --hardlink ~/Downloads
```
- SHA-256 based duplicate detection
- Interactive or automatic resolution
- Hardlink support to save space without deletion
- CSV/JSON export for reports

#### 4. **archive** - Age-Based File Archiving
Automatically archive old files to free up space.
```bash
zigstack archive --older-than 6mo --compress tar.gz --dest ~/Archive ~/Documents
```
- Archive files older than specified duration
- tar.gz compression support
- Preserve or flatten directory structure
- Category and size filtering

#### 5. **watch** - Automatic Organization
Monitor directories and automatically organize new files as they arrive.
```bash
zigstack watch --rules watch-rules.json ~/Downloads
```
- Real-time file monitoring
- Custom rules engine
- Configurable check intervals
- Logging and verbose output

#### 6. **workspace** - Developer Workspace Management
Clean up build artifacts and manage development projects.
```bash
zigstack workspace cleanup --strategy moderate ~/Code
```
- Auto-detect project types (Node.js, Python, Rust, Zig, Go, Java)
- Multiple cleanup strategies
- Inactive project detection
- Build artifact and dependency cleanup

## 🚀 Performance

All operations significantly exceed performance targets:

- **Extension Extraction**: 243M files/sec (2,430x target)
- **File Categorization**: 13M files/sec (263x target)
- **File Scanning**: 1.35M files/sec (1,351x target)
- **File Stats**: 351K files/sec (351x target)
- **Hash Calculation**: 30K files/sec (60x target)

Run `zig build benchmark` to verify performance on your system!

## 📚 Documentation

Complete documentation overhaul:

- **Getting Started Guide**: Quick installation and common workflows
- **Comprehensive FAQ**: 30+ questions covering all aspects
- **Troubleshooting Guide**: 50+ scenarios with solutions
- **Performance Guide**: Optimization tips and benchmarking
- **100+ Examples**: Covering all commands and use cases

Access documentation in the `docs/` directory or [online](https://github.com/jpequegn/zigstack/tree/main/docs).

## 🔄 Backward Compatibility

**100% backward compatible** with v0.2.0! All your existing scripts and workflows continue to work:

```bash
# v0.2.0 style (still works perfectly)
zigstack /path/to/directory
zigstack --move /path/to/directory
zigstack --by-date --move /path

# v0.3.0 style (new, explicit command)
zigstack organize /path/to/directory
zigstack organize --move /path/to/directory
zigstack organize --by-date --move /path
```

No migration required!

## 🏗️ Architecture

Completely refactored to a modular command-based architecture:

- **src/commands/**: Six independent command implementations
- **src/core/**: Shared core functionality
- **Extensible design**: Easy to add new commands
- **50+ tests**: Comprehensive test coverage

## 📦 Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/jpequegn/zigstack
cd zigstack

# Build (requires Zig 0.13.0 or later)
zig build

# Run
./zig-out/bin/zigstack --version
```

### Quick Start

```bash
# Organize messy downloads
zigstack organize --move ~/Downloads

# Find what's using disk space
zigstack analyze --top 20 ~/Documents

# Clean up duplicates
zigstack dedupe --auto keep-newest --delete ~/Photos

# Archive old files
zigstack archive --older-than 1y --dest ~/Archive ~/Documents

# Auto-organize downloads
zigstack watch ~/Downloads

# Clean dev workspace
zigstack workspace cleanup --strategy moderate ~/Code
```

## 🎯 Use Cases

### For Home Users
- Organize messy Downloads folders
- Find and remove duplicate photos
- Archive old documents
- Free up disk space

### For Developers
- Clean up build artifacts across projects
- Manage inactive projects
- Organize code repositories
- Monitor project directories

### For System Administrators
- Disk usage analysis and reporting
- Automated file organization
- Space reclamation
- Compliance and archiving

## 🔍 What's Next

### Planned for v0.4.0
- Daemon mode for watch command
- Parallel processing for multi-core systems
- Additional project types for workspace command
- Enhanced content analysis

### Under Consideration
- GUI interface
- Cloud storage integration
- Scheduled organization tasks
- Machine learning-based categorization

## 🙏 Acknowledgments

Thank you to everyone who provided feedback and suggestions during development!

## 📊 By The Numbers

- **6 commands** (1 → 6, 500% increase)
- **50+ tests** (comprehensive test coverage)
- **100+ examples** in documentation
- **1,400+ lines** of new documentation
- **10x - 2,000x** performance improvements
- **100% backward compatibility**

## 🐛 Bug Reports

Found a bug? Please [open an issue](https://github.com/jpequegn/zigstack/issues) on GitHub.

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete details of all changes.

## 💻 Links

- **GitHub**: https://github.com/jpequegn/zigstack
- **Documentation**: https://github.com/jpequegn/zigstack/tree/main/docs
- **Issues**: https://github.com/jpequegn/zigstack/issues
- **Releases**: https://github.com/jpequegn/zigstack/releases

---

**Happy organizing!** 🎉

The ZigStack Team
