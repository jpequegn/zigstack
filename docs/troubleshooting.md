# Troubleshooting Guide

This guide helps you resolve common issues with ZigStack.

## Installation Issues

### "zig: command not found"

**Problem**: Zig compiler is not installed or not in PATH.

**Solution**:
```bash
# Check if Zig is installed
zig version

# If not installed, download from https://ziglang.org/download/

# Add to PATH (Linux/macOS)
export PATH="$PATH:/path/to/zig"
```

### Build errors: "error: ZigCompiler requires version 0.13.0+"

**Problem**: Your Zig version is too old.

**Solution**:
```bash
# Check your Zig version
zig version

# Download Zig 0.13.0 or later from https://ziglang.org/download/
# Recommended: Zig 0.15.1
```

### "No such file or directory" when running zigstack

**Problem**: Binary not found or PATH not set.

**Solution**:
```bash
# Use full path
/path/to/zigstack/zig-out/bin/zigstack --help

# Or add to PATH
export PATH="$PATH:/path/to/zigstack/zig-out/bin"

# Or create alias
alias zigstack="/path/to/zigstack/zig-out/bin/zigstack"
```

## Permission Errors

### "Permission denied" when organizing files

**Problem**: Insufficient permissions to read/write files.

**Solution**:
```bash
# Check directory permissions
ls -la /path/to/directory

# Fix permissions (Linux/macOS)
chmod u+rw /path/to/directory
chmod u+rw /path/to/directory/*

# Run with sudo if necessary (use with caution!)
sudo zigstack organize --move /path/to/directory
```

### "Cannot create directory"

**Problem**: No write permission in target directory.

**Solution**:
```bash
# Check parent directory permissions
ls -la /parent/directory

# Fix permissions
chmod u+w /parent/directory

# Or specify a different target
zigstack organize --move /writable/path
```

## File Organization Issues

### Files not being organized

**Problem**: Files don't match known extensions or wrong mode.

**Solution**:
```bash
# 1. Check if running in dry-run mode (default)
zigstack organize --move /path  # Use --move to actually organize

# 2. Use verbose mode to see what's happening
zigstack organize --verbose /path

# 3. Check file extensions
ls -la /path | grep "unknown"

# 4. Use custom config for unknown extensions
zigstack organize --config custom-config.json --move /path
```

### "File already exists" conflicts

**Problem**: Destination file already exists.

**Solution**:
ZigStack automatically renames conflicting files:
- `file.txt` → `file_1.txt`
- `photo.jpg` → `photo_1.jpg`

This is automatic and prevents overwrites.

### Organization creates unexpected structure

**Problem**: Date-based or size-based organization not as expected.

**Solution**:
```bash
# Check what options are active
zigstack organize --verbose --dry-run /path

# Date-based creates: 2024/09/Documents/
# Size-based creates: large_files/ and regular_files/
# Combined creates: 2024/09/large_files/

# Disable unwanted options
zigstack organize --move /path  # Basic organization only
```

## Duplicate Detection Issues

### Duplicate detection is slow

**Problem**: Hashing large files takes time.

**Solution**:
```bash
# 1. Filter by minimum file size
zigstack dedupe --min-size 1048576 /path  # Only files > 1MB

# 2. Limit to specific directory depth
zigstack dedupe --max-depth 3 /path

# 3. Use summary mode for quick overview
zigstack dedupe --summary /path

# 4. Be patient - hashing 1GB file takes ~5-10 seconds
```

### Duplicates not detected

**Problem**: Files are identical but not reported as duplicates.

**Solution**:
```bash
# 1. Ensure files are truly identical
md5sum file1.txt file2.txt  # Should match

# 2. Check minimum size threshold
zigstack dedupe --min-size 0 /path  # Include all sizes

# 3. Use verbose mode
zigstack dedupe --verbose /path

# 4. Verify recursive mode is enabled
zigstack dedupe --recursive /path
```

### "Cannot hardlink across filesystems"

**Problem**: Trying to hardlink files on different partitions.

**Solution**:
Hardlinks only work on the same filesystem. Options:
```bash
# 1. Use delete instead of hardlink
zigstack dedupe --auto keep-newest --delete /path

# 2. Or keep duplicates
zigstack dedupe --summary /path  # Just report them

# 3. Move files to same filesystem first
mv /other/partition/files /same/partition/
zigstack dedupe --auto keep-newest --hardlink /same/partition/
```

## Watch Command Issues

### Watch command not detecting new files

**Problem**: New files aren't being organized.

**Solution**:
```bash
# 1. Check if watch is actually running
ps aux | grep zigstack

# 2. Verify directory path
zigstack watch --verbose ~/Downloads

# 3. Check log file
tail -f ~/.local/share/zigstack/watch.log

# 4. Try with shorter interval
zigstack watch --interval 3 ~/Downloads
```

### Invalid rules file

**Problem**: Watch rules file has syntax errors.

**Solution**:
```bash
# Validate rules before running
zigstack watch --validate-rules --rules watch-rules.json

# Check JSON syntax
cat watch-rules.json | jq .  # Requires jq tool

# See example rules
cat examples/WATCH_RULES.md
```

### Watch using too much CPU

**Problem**: Watch command consuming excessive resources.

**Solution**:
```bash
# 1. Increase check interval
zigstack watch --interval 30 ~/Downloads  # Check every 30 seconds

# 2. Limit to specific directory (don't watch ~/)
zigstack watch ~/Downloads  # Not zigstack watch ~/

# 3. Use simpler rules
# Avoid complex regex patterns in rules file
```

## Workspace Command Issues

### Projects not detected

**Problem**: Workspace scan doesn't find your projects.

**Solution**:
```bash
# 1. Use verbose mode
zigstack workspace scan --verbose ~/Code

# 2. Check supported project types
# Currently: nodejs, python, rust, zig, go, java

# 3. Ensure project markers exist
# Node.js: package.json
# Python: requirements.txt, setup.py
# Rust: Cargo.toml
# Zig: build.zig
```

### Cleanup removed too much / too little

**Problem**: Cleanup strategy not appropriate.

**Solution**:
```bash
# Always preview first!
zigstack workspace cleanup --dry-run ~/Code

# Adjust strategy
zigstack workspace cleanup --strategy conservative ~/Code  # Safest
zigstack workspace cleanup --strategy moderate ~/Code      # Balanced
zigstack workspace cleanup --strategy aggressive ~/Code    # Most cleanup

# Fine-tune what gets removed
zigstack workspace cleanup --artifacts-only ~/Code  # Keep dependencies
zigstack workspace cleanup --deps-only ~/Code       # Keep artifacts
zigstack workspace cleanup --inactive-only ~/Code   # Only old projects
```

## Archive Command Issues

### Files not being archived

**Problem**: No files match age threshold.

**Solution**:
```bash
# 1. Check file modification times
ls -lt /path/to/directory

# 2. Use appropriate age threshold
zigstack archive --older-than 1d --dest ~/Archive /path   # Very recent
zigstack archive --older-than 7d --dest ~/Archive /path   # Last week
zigstack archive --older-than 1mo --dest ~/Archive /path  # Last month

# 3. Verify with dry-run
zigstack archive --dry-run --older-than 6mo --dest ~/Archive /path
```

### "Destination directory does not exist"

**Problem**: Archive destination doesn't exist.

**Solution**:
```bash
# Create destination first
mkdir -p ~/Archive

# Then run archive
zigstack archive --older-than 6mo --dest ~/Archive /documents
```

### Compression fails

**Problem**: tar.gz compression error.

**Solution**:
```bash
# 1. Ensure enough disk space
df -h

# 2. Check permissions on destination
ls -la ~/Archive

# 3. Try without compression first
zigstack archive --older-than 6mo --dest ~/Archive /path

# 4. Verify tar is available
which tar
```

## Performance Issues

### ZigStack running slowly

**Problem**: Operations taking longer than expected.

**Solution**:
```bash
# 1. Reduce scope
zigstack organize --max-depth 2 /path  # Don't recurse too deep

# 2. Filter by size
zigstack analyze --min-size 10 /path  # Skip files <10MB

# 3. Limit results
zigstack analyze --top 10 /path  # Show only top 10

# 4. Disable expensive features
zigstack analyze /path  # Don't use --content flag
```

### High memory usage

**Problem**: ZigStack consuming too much memory.

**Solution**:
```bash
# 1. Process directories in smaller batches
zigstack organize ~/Documents/2024
zigstack organize ~/Documents/2023
# Instead of: zigstack organize ~/Documents

# 2. Use streaming operations
zigstack dedupe --min-size 10485760 /path  # Only large files

# 3. Monitor memory
top -p $(pgrep zigstack)
```

## Output & Export Issues

### JSON output is invalid

**Problem**: Cannot parse JSON output.

**Solution**:
```bash
# 1. Ensure only JSON is output (no verbose messages)
zigstack analyze --json /path > output.json

# 2. Validate JSON
cat output.json | jq .

# 3. Use output flag instead of redirect
zigstack analyze --json --output report.json /path
```

### CSV export formatting issues

**Problem**: CSV not opening correctly in Excel/Sheets.

**Solution**:
```bash
# 1. Specify output file
zigstack dedupe --format csv --output duplicates.csv /path

# 2. Check CSV manually
cat duplicates.csv | head

# 3. Try different CSV viewer
# Excel, Google Sheets, LibreOffice Calc, etc.
```

## Getting More Help

### Enable Verbose Output

For any issue, try verbose mode first:
```bash
zigstack <command> --verbose [options] /path
```

### Check Version

Ensure you're on the latest version:
```bash
zigstack --version
```

### Review Logs

Watch command creates logs:
```bash
# Default log location
tail -f ~/.local/share/zigstack/watch.log

# Custom log location
zigstack watch --log /tmp/my-watch.log ~/Downloads
tail -f /tmp/my-watch.log
```

### Report Bugs

If you've found a bug:
1. Try to reproduce with minimal example
2. Note your OS, Zig version, ZigStack version
3. Include relevant error messages
4. Open an issue on GitHub with details

## Common Error Messages

### "Invalid argument"
- Check command syntax: `zigstack <command> --help`
- Verify all required arguments are provided
- Check for typos in flag names

### "No such file or directory"
- Verify path exists: `ls -la /path/to/directory`
- Use absolute paths when possible
- Check for typos in path

### "Out of memory"
- Reduce scope of operation
- Process in smaller batches
- Close other applications

### "Operation not permitted"
- Check file/directory permissions
- Don't run as sudo unless necessary
- Verify ownership: `ls -la /path`

## Still Having Issues?

- Read the [FAQ](FAQ.md)
- Check command-specific documentation in [commands/](commands/)
- Review the [Getting Started Guide](getting-started.md)
- Open an issue on GitHub with:
  - Your OS and version
  - Zig version (`zig version`)
  - ZigStack version (`zigstack --version`)
  - Complete error message
  - Steps to reproduce
  - Output of `zigstack <command> --verbose`
