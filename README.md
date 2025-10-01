# zigstack

A powerful command-line file organization tool written in Zig that automatically categorizes and organizes files in directories based on file extensions.

## Features

- **Smart File Categorization**: Automatically categorizes files into Documents, Images, Videos, Audio, Archives, Code, Data, Configuration, and Other
- **Advanced Organization Options**:
  - **Date-based organization**: Organize files by creation or modification time (year, year-month, year-month-day)
  - **Size-based organization**: Separate large files from regular files with customizable size threshold
  - **Duplicate file detection**: Find and handle duplicate files with multiple strategies (skip, rename, replace, keep-both)
  - **Recursive directory processing**: Process subdirectories with configurable depth control
- **Custom Configuration**: Support for JSON configuration files to define custom categories and file extensions
- **Safe Operations**: Dry-run mode to preview changes before execution
- **Conflict Resolution**: Automatic file renaming when conflicts occur
- **Rollback Support**: Ability to rollback file moves in case of errors
- **Comprehensive Logging**: Verbose output for detailed operation tracking
- **Edge Case Handling**: Robust handling of special characters, long filenames, empty files, and various edge cases

## Installation

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.13.0 or later

### Build from Source

1. Clone the repository:
```bash
git clone <repository-url>
cd zigstack
```

2. Build the project:
```bash
zig build
```

3. The executable will be created in `zig-out/bin/zigstack`

4. (Optional) Add to your PATH or create an alias:
```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
alias zigstack="/path/to/zigstack/zig-out/bin/zigstack"
```

## Usage

### Basic Syntax

```bash
zigstack [OPTIONS] <directory>
# or
zigstack <command> [OPTIONS] <directory>
```

### Command-Based Interface (v0.3.0+)

Starting with v0.3.0, ZigStack supports a command-based interface while maintaining 100% backward compatibility with v0.2.0 usage patterns.

#### Available Commands
- `organize` - Organize files by extension, date, size, or duplicates (default command)

#### Backward Compatibility

**All v0.2.0 usage patterns continue to work exactly as before:**

```bash
# v0.2.0 style (still works)
zigstack /path/to/directory
zigstack --move /path/to/directory
zigstack --by-date --move /path
zigstack --verbose --dry-run /path

# v0.3.0 style (new, explicit command)
zigstack organize /path/to/directory
zigstack organize --move /path/to/directory
zigstack organize --by-date --move /path
zigstack organize --verbose --dry-run /path
```

Both styles produce identical results. The command-based interface is optional and provides a foundation for future commands while ensuring existing scripts and workflows remain unaffected.

#### Migration Guide

**No migration required!** Your existing scripts, aliases, and workflows will continue to work without any changes.

If you want to use the new command-based interface:
- Simply prefix your existing commands with `organize`
- All flags and options remain the same
- Help is available with `zigstack organize --help`

**Future commands** (planned for future releases):
- `zigstack stats` - Analyze directory statistics
- `zigstack search` - Search for files by various criteria
- `zigstack compare` - Compare directory structures

### Command-Line Options

#### Basic Options
- `-h, --help` - Display help message
- `-v, --version` - Display version information
- `--config PATH` - Specify custom configuration file (JSON format)
- `-c, --create` - Create directories (preview mode by default)
- `-m, --move` - Move files to directories (implies --create)
- `-d, --dry-run` - Show what would happen without doing it (default mode)
- `-V, --verbose` - Enable verbose logging

#### Advanced Organization Options
- `--by-date` - Organize files by date (creation or modification time)
- `--date-format FORMAT` - Date organization format: year, year-month, year-month-day (default: year-month)
- `--by-size` - Separate large files from regular files
- `--size-threshold MB` - Size threshold for large files in MB (default: 100)
- `--detect-dups` - Enable duplicate file detection
- `--dup-action ACTION` - How to handle duplicates: skip, rename, replace, keep-both (default: skip)
- `--recursive` - Process subdirectories recursively
- `--max-depth DEPTH` - Maximum recursion depth (default: 10)

### Examples

#### Preview File Organization (Default Mode)
```bash
# Analyze a directory and show how files would be organized
zigstack /path/to/directory

# Same as above with explicit dry-run flag
zigstack --dry-run /path/to/directory
```

#### Create Directories Only
```bash
# Create category directories without moving files
zigstack --create /path/to/directory
```

#### Full Organization (Create and Move)
```bash
# Create directories and move files into them
zigstack --move /path/to/directory
```

#### Using Custom Configuration
```bash
# Use a custom configuration file for categorization
zigstack --config my-config.json --move /path/to/directory
```

#### Verbose Output
```bash
# Get detailed information about operations
zigstack --verbose --move /path/to/directory
```

#### Advanced Organization Examples

##### Date-based Organization
```bash
# Organize files by creation/modification year and month
zigstack --by-date --move /path/to/directory

# Organize files by year only
zigstack --by-date --date-format year --move /path/to/directory

# Organize files by full date (year/month/day)
zigstack --by-date --date-format year-month-day --move /path/to/directory
```

##### Size-based Organization
```bash
# Separate large files (>100MB) from regular files
zigstack --by-size --move /path/to/directory

# Use custom size threshold (>50MB)
zigstack --by-size --size-threshold 50 --move /path/to/directory
```

##### Duplicate File Detection
```bash
# Find and skip duplicate files (default behavior)
zigstack --detect-dups --move /path/to/directory

# Rename duplicate files (file.txt → file_1.txt, file_2.txt, etc.)
zigstack --detect-dups --dup-action rename --move /path/to/directory

# Replace duplicate files (keep the last one processed)
zigstack --detect-dups --dup-action replace --move /path/to/directory

# Keep both files with different names
zigstack --detect-dups --dup-action keep-both --move /path/to/directory
```

##### Recursive Directory Processing
```bash
# Process all subdirectories (up to 10 levels deep by default)
zigstack --recursive --move /path/to/directory

# Limit recursion depth to 3 levels
zigstack --recursive --max-depth 3 --move /path/to/directory
```

##### Combined Advanced Features
```bash
# Organize by date with duplicate detection and recursive processing
zigstack --by-date --detect-dups --recursive --move /path/to/directory

# Size-based organization with custom threshold, recursive processing, and verbose output
zigstack --by-size --size-threshold 200 --recursive --max-depth 5 --verbose --move /path/to/directory

# Full feature demonstration: date organization, duplicate handling, size separation, recursive
zigstack --by-date --date-format year-month-day \
         --detect-dups --dup-action rename \
         --by-size --size-threshold 100 \
         --recursive --max-depth 3 \
         --verbose --move /path/to/directory
```

### Example Output

#### Standard Organization
```
============================================================
FILE ORGANIZATION - MOVING FILES
============================================================

Total files to organize: 12

Files grouped by category:
----------------------------------------

📁 Documents (3 files):
    • report.pdf (.pdf)
    • notes.txt (.txt)
    • presentation.docx (.docx)

📁 Images (4 files):
    • photo1.jpg (.jpg)
    • logo.png (.png)
    • diagram.svg (.svg)
    • screenshot.webp (.webp)

📁 Code (5 files):
    • main.zig (.zig)
    • script.py (.py)
    • config.json (.json)
    • style.css (.css)
    • index.html (.html)

Organization Summary:
----------------------------------------
  Documents: 3 files (25.0%)
  Images: 4 files (33.3%)
  Code: 5 files (41.7%)

============================================================
Directory creation and file moving complete.
============================================================
```

#### Date-based Organization Output
```
============================================================
FILE ORGANIZATION - DATE-BASED ORGANIZATION
============================================================

Total files to organize: 15

Files organized by date:
----------------------------------------

📁 2024/09 (8 files):
    📁 Documents (3 files):
        • report.pdf (.pdf)
        • notes.txt (.txt)
        • presentation.docx (.docx)
    📁 Images (5 files):
        • photo1.jpg (.jpg)
        • logo.png (.png)
        • diagram.svg (.svg)
        • screenshot.webp (.webp)
        • banner.gif (.gif)

📁 2024/08 (4 files):
    📁 Code (2 files):
        • main.zig (.zig)
        • script.py (.py)
    📁 Data (2 files):
        • database.json (.json)
        • config.yaml (.yaml)

📁 2024/07 (3 files):
    📁 Audio (2 files):
        • song.mp3 (.mp3)
        • podcast.wav (.wav)
    📁 Videos (1 files):
        • demo.mp4 (.mp4)

Organization Summary:
----------------------------------------
  2024/09: 8 files (53.3%)
  2024/08: 4 files (26.7%)
  2024/07: 3 files (20.0%)

============================================================
Date-based organization complete.
============================================================
```

#### Size-based Organization Output
```
============================================================
FILE ORGANIZATION - SIZE-BASED ORGANIZATION
============================================================

Total files to organize: 10

Files organized by size:
----------------------------------------

📁 Large Files (>100MB) (3 files):
    • large_video.mp4 (450.2 MB)
    • backup_archive.zip (235.8 MB)
    • high_res_image.tiff (125.4 MB)

📁 Regular Files (7 files):
    📁 Documents (2 files):
        • report.pdf (2.1 MB)
        • notes.txt (15.2 KB)
    📁 Images (3 files):
        • photo.jpg (850.5 KB)
        • logo.png (45.3 KB)
        • icon.svg (8.2 KB)
    📁 Code (2 files):
        • main.zig (12.4 KB)
        • script.py (3.7 KB)

Organization Summary:
----------------------------------------
  Large Files: 3 files (30.0%) - 811.4 MB total
  Regular Files: 7 files (70.0%) - 45.8 MB total

============================================================
Size-based organization complete.
============================================================
```

## Configuration File

### Default Categories

zigstack comes with built-in categories for common file types:

- **Documents**: `.txt`, `.pdf`, `.doc`, `.docx`, `.md`, `.rtf`, `.odt`, `.tex`
- **Images**: `.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp`, `.svg`, `.webp`, `.ico`
- **Videos**: `.mp4`, `.avi`, `.mkv`, `.mov`, `.wmv`, `.flv`, `.webm`
- **Audio**: `.mp3`, `.wav`, `.flac`, `.aac`, `.ogg`, `.m4a`, `.wma`
- **Archives**: `.zip`, `.tar`, `.gz`, `.rar`, `.7z`, `.bz2`, `.xz`
- **Code**: `.c`, `.cpp`, `.h`, `.py`, `.js`, `.ts`, `.java`, `.zig`, `.rs`, `.go`, `.sh`
- **Data**: `.json`, `.xml`, `.csv`, `.sql`, `.db`, `.sqlite`
- **Configuration**: `.ini`, `.cfg`, `.conf`, `.yaml`, `.yml`, `.toml`
- **Other**: Files that don't match any category

### Custom Configuration

Create a JSON configuration file to customize categories and file extensions:

```json
{
  "version": "1.0",
  "categories": {
    "MyDocuments": {
      "description": "My custom document types",
      "extensions": [".mydoc", ".notes"],
      "color": "#4A90E2",
      "priority": 1
    },
    "ProjectFiles": {
      "description": "Project-specific files",
      "extensions": [".proj", ".workspace"],
      "color": "#7ED321",
      "priority": 2
    }
  },
  "display": {
    "show_categories": true,
    "show_colors": false,
    "group_by_category": true,
    "sort_categories_by_priority": true,
    "show_category_summaries": true,
    "show_uncategorized": true,
    "uncategorized_label": "Other"
  },
  "behavior": {
    "case_sensitive_extensions": false,
    "include_hidden_files": false,
    "include_directories": false,
    "max_depth": 1
  }
}
```

## Directory Structure

### Standard Organization
After basic organization, your directory will look like:

```
/your/directory/
├── documents/
│   ├── report.pdf
│   └── notes.txt
├── images/
│   ├── photo1.jpg
│   └── logo.png
├── code/
│   ├── main.zig
│   └── script.py
└── misc/
    └── unknown_file
```

### Date-based Organization
With `--by-date --date-format year-month`:

```
/your/directory/
├── 2024/
│   ├── 09/
│   │   ├── documents/
│   │   │   ├── recent_report.pdf
│   │   │   └── meeting_notes.txt
│   │   └── images/
│   │       └── recent_photo.jpg
│   ├── 08/
│   │   ├── code/
│   │   │   └── old_script.py
│   │   └── data/
│   │       └── backup.json
│   └── 07/
│       └── audio/
│           └── old_recording.mp3
└── 2023/
    └── 12/
        └── documents/
            └── archive_document.pdf
```

### Size-based Organization
With `--by-size`:

```
/your/directory/
├── large_files/           # Files > size threshold
│   ├── huge_video.mp4     # 500MB
│   ├── large_archive.zip  # 250MB
│   └── big_dataset.csv    # 150MB
└── regular_files/         # Files <= size threshold
    ├── documents/
    │   ├── report.pdf     # 2MB
    │   └── notes.txt      # 15KB
    ├── images/
    │   └── photo.jpg      # 800KB
    └── code/
        └── script.py      # 5KB
```

### Combined Organization
With `--by-date --by-size`:

```
/your/directory/
├── 2024/
│   ├── 09/
│   │   ├── large_files/
│   │   │   └── presentation_video.mp4  # 300MB
│   │   └── regular_files/
│   │       ├── documents/
│   │       │   └── report.pdf          # 2MB
│   │       └── images/
│   │           └── chart.png           # 500KB
│   └── 08/
│       └── regular_files/
│           └── code/
│               └── script.py           # 5KB
└── 2023/
    └── 12/
        └── large_files/
            └── archive.zip             # 1GB
```

## Safety Features

### Dry-Run Mode
By default, zigstack runs in preview mode, showing you exactly what it would do without making any changes.

### Conflict Resolution
When a file with the same name already exists in the destination directory, zigstack automatically renames the file by appending a number:
- `document.txt` → `document_1.txt`
- `photo.jpg` → `photo_1.jpg`

### Rollback Support
If an error occurs during file moving, zigstack can automatically rollback all changes, restoring files to their original locations.

## Development

### Running Tests

```bash
# Run all tests
zig build test

# Run with verbose output
zig build test --verbose
```

### Building in Debug Mode

```bash
# Build with debug information
zig build -Doptimize=Debug
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass: `zig build test`
6. Submit a pull request

## Edge Cases Handled

zigstack robustly handles various edge cases:

### Basic Edge Cases
- **Empty files**: Organized based on extension, regardless of file size
- **Files without extensions**: Categorized as "Other"
- **Special characters**: Filenames with spaces, dashes, underscores, and numbers
- **Hidden files**: Files starting with `.` (can be included with configuration)
- **Long filenames**: Proper handling of filesystem limits
- **Invalid characters**: Safe handling of unusual characters in filenames
- **Permission issues**: Clear error messages and graceful handling
- **Disk space**: Checking for available space before operations

### Advanced Feature Edge Cases
- **Date-based organization**:
  - Files with invalid or missing timestamps (fallback to current time)
  - Future dates (properly handled without issues)
  - Files from different time zones
  - Leap years and month boundaries
- **Size-based organization**:
  - Zero-byte files (treated as regular files)
  - Extremely large files (>1TB, proper memory management)
  - Sparse files and symbolic links
- **Duplicate detection**:
  - Files with identical content but different names
  - Files with same name but different content
  - Binary files, text files, and special file types
  - Large files (streaming hash calculation to avoid memory issues)
- **Recursive processing**:
  - Symbolic link cycles (prevented with path tracking)
  - Deep directory structures (configurable depth limits)
  - Permission issues in subdirectories (graceful handling)
  - Mixed file systems and junction points

## License

[License information would go here]

## Version History

- **v0.3.0** (In Development): Command infrastructure and backward compatibility (Issues #17, #18, #19)
  - **Command-based interface**: New subcommand system with `organize` command
  - **100% backward compatibility**: All v0.2.0 CLI patterns continue to work unchanged
  - **Modular architecture**: Refactored codebase with separate command and core modules
  - **Enhanced testing**: 20+ new tests for command routing and backward compatibility
  - **Future-ready**: Foundation for additional commands (stats, search, compare, etc.)
  - **Comprehensive documentation**: Updated README with migration guide and examples

- **v0.2.0**: Advanced organization features (Issue #8)
  - **Date-based organization**: Organize files by creation/modification time with configurable date formats
  - **Size-based organization**: Separate large files from regular files with customizable thresholds
  - **Duplicate file detection**: SHA-256 based duplicate detection with multiple handling strategies
  - **Recursive directory processing**: Process subdirectories with configurable depth control
  - Enhanced command-line interface with 8 new options
  - Comprehensive test suite for all new features
  - Updated documentation with examples and usage patterns

- **v0.1.0**: Initial release with basic file organization features
  - File categorization by extension
  - Directory creation and file moving
  - Dry-run preview mode
  - Custom configuration support
  - Basic test suite

## Support

For issues, feature requests, or questions, please open an issue in the GitHub repository.