# zigstack

A powerful command-line file organization tool written in Zig that automatically categorizes and organizes files in directories based on file extensions.

## Features

- **Smart File Categorization**: Automatically categorizes files into Documents, Images, Videos, Audio, Archives, Code, Data, Configuration, and Other
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
```

### Command-Line Options

- `-h, --help` - Display help message
- `-v, --version` - Display version information
- `--config PATH` - Specify custom configuration file (JSON format)
- `-c, --create` - Create directories (preview mode by default)
- `-m, --move` - Move files to directories (implies --create)
- `-d, --dry-run` - Show what would happen without doing it (default mode)
- `-V, --verbose` - Enable verbose logging

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

### Example Output

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

After organization, your directory will look like:

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

- **Empty files**: Organized based on extension, regardless of file size
- **Files without extensions**: Categorized as "Other"
- **Special characters**: Filenames with spaces, dashes, underscores, and numbers
- **Hidden files**: Files starting with `.` (can be included with configuration)
- **Long filenames**: Proper handling of filesystem limits
- **Invalid characters**: Safe handling of unusual characters in filenames
- **Permission issues**: Clear error messages and graceful handling
- **Disk space**: Checking for available space before operations

## License

[License information would go here]

## Version History

- **v0.1.0**: Initial release with basic file organization features
  - File categorization by extension
  - Directory creation and file moving
  - Dry-run preview mode
  - Custom configuration support
  - Comprehensive test suite

## Support

For issues, feature requests, or questions, please open an issue in the GitHub repository.