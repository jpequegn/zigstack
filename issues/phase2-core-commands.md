# Phase 2: Core Commands - GitHub Issues

## Issue #15: Implement 'organize' Command Module

**Title**: Extract existing functionality into 'organize' command

**Description**:
Move current file organization functionality into a dedicated command module while maintaining all existing features.

**Tasks**:
- [ ] Create `src/commands/organize.zig`
- [ ] Move organization logic from main.zig to organize command
- [ ] Implement Command interface for organize
- [ ] Preserve all existing options (--by-date, --by-size, etc.)
- [ ] Update help text for organize command
- [ ] Add command-specific tests
- [ ] Update documentation with new command structure

**Command Signature**:
```bash
zigstack organize [OPTIONS] <directory>
# Or implicitly: zigstack [OPTIONS] <directory>
```

**Acceptance Criteria**:
- All existing functionality works through organize command
- Backward compatibility maintained
- Command help displays all options
- Tests verify all organization modes (date, size, duplicate, recursive)
- Performance matches or exceeds current implementation

**Estimated Effort**: 4-5 hours

**Dependencies**: Phase 1 complete (Issues #10-14)

**Labels**: command, organize, refactoring

---

## Issue #16: Implement 'analyze' Command - Disk Usage

**Title**: Create disk usage analysis command

**Description**:
Implement disk space analysis with visualization, showing directory and file type breakdowns.

**Tasks**:
- [ ] Create `src/commands/analyze.zig`
- [ ] Implement directory tree traversal with size calculation
- [ ] Calculate size by category (Documents, Images, Videos, etc.)
- [ ] Add size distribution visualization (ASCII bar charts)
- [ ] Implement top-N largest files/directories
- [ ] Add filtering options (--min-size, --max-depth)
- [ ] Support JSON export for programmatic use
- [ ] Write comprehensive tests

**Features**:
```bash
zigstack analyze /path
# Output:
# Disk Usage Analysis
# ==================
# Total: 15.3 GB across 4,582 files
#
# By Category:
# Videos     ████████████████████ 8.2 GB (53.6%)
# Images     ██████████           3.4 GB (22.2%)
# Documents  ████                 1.5 GB (9.8%)
# Code       ███                  1.2 GB (7.8%)
# Other      ██                   1.0 GB (6.5%)
#
# Largest Files:
# 1. movie.mp4                    2.1 GB
# 2. backup.zip                   1.8 GB
# 3. presentation.pptx            450 MB
```

**Options**:
- `--min-size <SIZE>`: Only show files/dirs above size
- `--max-depth <N>`: Limit directory traversal depth
- `--format json|text`: Output format
- `--top <N>`: Show top N largest items (default: 10)
- `--sort size|count|name`: Sort criteria

**Acceptance Criteria**:
- Accurate size calculations including sparse files
- Fast performance (>1000 files/sec)
- ASCII visualization renders correctly
- JSON export is valid and parseable
- Tests cover edge cases (empty dirs, symlinks, permissions)

**Estimated Effort**: 6-8 hours

**Dependencies**: Phase 1 complete

**Labels**: command, analyze, enhancement, feature

---

## Issue #17: Implement 'analyze' Command - Content Analysis

**Title**: Add content-based file analysis to analyze command

**Description**:
Extend analyze command with content inspection for images, videos, documents, and code files.

**Tasks**:
- [ ] Add image metadata reading (dimensions, format, color depth)
- [ ] Add video metadata reading (duration, resolution, codec)
- [ ] Add audio metadata reading (duration, bitrate, format)
- [ ] Add document analysis (word count, page count for PDFs)
- [ ] Add code analysis (lines of code, language detection)
- [ ] Implement --content flag to enable detailed analysis
- [ ] Handle errors gracefully for corrupted/unreadable files
- [ ] Write tests with sample media files

**Content Analysis Output**:
```bash
zigstack analyze --content /photos
# Images Analysis
# ===============
# Total: 342 images
# Resolutions:
#   4K (3840x2160):     45 images
#   1080p (1920x1080): 180 images
#   720p (1280x720):    89 images
#   Other:              28 images
# Formats: JPEG (280), PNG (45), GIF (12), WebP (5)
```

**Libraries/Techniques**:
- Use file magic numbers for format detection
- Parse image headers (JPEG EXIF, PNG chunks, etc.)
- Parse video containers (MP4, MKV) for metadata
- Count lines/words for text files
- Keep dependencies minimal (prefer pure Zig implementations)

**Acceptance Criteria**:
- Accurately reads metadata from common formats
- Handles corrupted files without crashing
- Performance impact is acceptable (--content is optional)
- Tests include various file formats
- Documentation lists supported formats

**Estimated Effort**: 8-10 hours

**Dependencies**: Issue #16

**Labels**: command, analyze, enhancement, feature, media

---

## Issue #18: Implement 'dedupe' Command - Basic Functionality

**Title**: Create interactive duplicate file management command

**Description**:
Implement a dedicated command for finding and managing duplicate files with interactive resolution.

**Tasks**:
- [ ] Create `src/commands/dedupe.zig`
- [ ] Implement duplicate detection using existing hash logic
- [ ] Group duplicates by hash with file details
- [ ] Calculate space savings from deduplication
- [ ] Add interactive mode for duplicate resolution
- [ ] Support batch actions (keep-oldest, keep-newest, keep-largest)
- [ ] Implement dry-run mode for safety
- [ ] Write tests with duplicate file scenarios

**Command Interface**:
```bash
zigstack dedupe /path
# Found 23 duplicate files (3.2 GB can be saved)
#
# Duplicate Group 1: photo.jpg (2.1 MB, 3 copies)
#   [1] /photos/2023/photo.jpg (modified: 2023-05-01)
#   [2] /backup/photo.jpg (modified: 2023-05-01)
#   [3] /downloads/photo.jpg (modified: 2023-05-02)
# Action [k]eep 1, [d]elete all, [s]kip, [?]help:
```

**Options**:
- `--auto <STRATEGY>`: Automatic resolution (keep-oldest, keep-newest, keep-largest)
- `--interactive`: Interactive mode (default)
- `--summary`: Show summary only, no actions
- `--format json|text`: Output format

**Acceptance Criteria**:
- Finds all duplicates accurately
- Interactive mode is user-friendly
- Automatic modes work correctly
- Dry-run shows planned actions
- Tests verify duplicate detection and resolution

**Estimated Effort**: 5-7 hours

**Dependencies**: Phase 1 complete

**Labels**: command, dedupe, enhancement, feature

---

## Issue #19: Implement 'dedupe' Command - Hardlink Support

**Title**: Add hardlink creation option to dedupe command

**Description**:
Add ability to replace duplicate files with hardlinks for space savings without deletion.

**Tasks**:
- [ ] Implement hardlink creation in dedupe command
- [ ] Add --hardlink flag and strategy
- [ ] Verify filesystem hardlink support
- [ ] Check inode limits and handle errors
- [ ] Calculate space savings from hardlinking
- [ ] Add tests for hardlink operations
- [ ] Document hardlink behavior and limitations

**Hardlink Strategy**:
```bash
zigstack dedupe --hardlink /path
# Replaces duplicate files with hardlinks
# - Keeps one original file
# - Other copies become hardlinks to original
# - Space is freed immediately
# - Files remain accessible at all paths
```

**Safety Checks**:
- Verify files are on same filesystem (hardlinks can't cross filesystems)
- Check file permissions before linking
- Handle read-only files appropriately
- Warn about hardlink limitations (editing affects all links)

**Acceptance Criteria**:
- Hardlinks created correctly
- Space savings calculated accurately
- Filesystem compatibility checked
- Clear warnings about hardlink behavior
- Tests verify hardlink functionality

**Estimated Effort**: 4-5 hours

**Dependencies**: Issue #18

**Labels**: command, dedupe, enhancement, feature, advanced

---

## Issue #20: Add Export and Reporting Features

**Title**: Implement JSON/CSV export for all commands

**Description**:
Add consistent export functionality across commands for automation and integration.

**Tasks**:
- [ ] Create `src/core/export.zig` module
- [ ] Implement JSON export format
- [ ] Implement CSV export format
- [ ] Add --format flag to all commands
- [ ] Add --output flag to specify file path
- [ ] Ensure exported data is complete and structured
- [ ] Add tests for export functionality
- [ ] Document export formats

**Export Formats**:

**organize** command:
```json
{
  "command": "organize",
  "timestamp": "2024-01-15T10:30:00Z",
  "directory": "/path/to/dir",
  "total_files": 1234,
  "categories": {
    "Documents": {"count": 456, "size_bytes": 123456789},
    "Images": {"count": 678, "size_bytes": 987654321}
  },
  "actions": [
    {"file": "doc.pdf", "action": "moved", "from": "/path/doc.pdf", "to": "/path/documents/doc.pdf"}
  ]
}
```

**analyze** command:
```json
{
  "command": "analyze",
  "timestamp": "2024-01-15T10:30:00Z",
  "directory": "/path/to/dir",
  "total_size_bytes": 123456789,
  "total_files": 1234,
  "by_category": {...},
  "largest_files": [...]
}
```

**Acceptance Criteria**:
- JSON is valid and well-formatted
- CSV is parseable by standard tools
- All relevant data is exported
- Export doesn't impact performance significantly
- Documentation includes format specifications

**Estimated Effort**: 5-6 hours

**Dependencies**: Issues #15, #16, #18

**Labels**: command, export, enhancement, feature

---

## Phase 2 Summary

**Total Estimated Effort**: 32-41 hours
**Total Issues**: 6 (Issues #15-20)

**Implementation Order**:
1. Issue #15 (organize command) - Validate command infrastructure
2. Issue #16 (analyze disk usage) - First new command
3. Issue #17 (analyze content) - Extend analyze
4. Issue #18 (dedupe basic) - New command
5. Issue #19 (dedupe hardlink) - Extend dedupe
6. Issue #20 (export) - Cross-cutting feature

**Deliverables**:
- 3 fully functional commands (organize, analyze, dedupe)
- JSON/CSV export capability
- Comprehensive test coverage
- Updated documentation
