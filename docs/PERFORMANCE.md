# ZigStack Performance

Performance characteristics and benchmarking information for ZigStack.

## Performance Targets

ZigStack is designed for high performance file operations:

| Operation | Target | Achieved | Status |
|-----------|--------|----------|---------|
| Extension Extraction | >100K files/sec | **243M files/sec** | ✅ 2,430x target |
| File Categorization | >50K files/sec | **13M files/sec** | ✅ 263x target |
| File Scanning | >1K files/sec | **1.35M files/sec** | ✅ 1,351x target |
| File Stats Retrieval | >1K files/sec | **351K files/sec** | ✅ 351x target |
| Hash Calculation (Dedupe) | >500 files/sec | **30K files/sec** | ✅ 60x target |

*Benchmarks run on Apple M-series silicon with ReleaseFast optimization*

## Benchmarking

### Running Benchmarks

```bash
# Run all performance benchmarks
zig build benchmark

# View benchmark with specific optimization level
zig build benchmark -Doptimize=ReleaseFast  # Maximum performance
zig build benchmark -Doptimize=ReleaseSafe  # With safety checks
zig build benchmark -Doptimize=Debug        # Debug build
```

### Benchmark Suite

The benchmark suite includes:

1. **Extension Extraction** - Tests string manipulation for file extension extraction
2. **File Categorization** - Tests categorization logic for file types
3. **File Scanning** - Tests directory iteration and file discovery
4. **File Stats Retrieval** - Tests filesystem stat operations
5. **Hash Calculation** - Tests SHA-256 hashing for duplicate detection

### Sample Output

```
============================================================
ZigStack Performance Benchmarks
============================================================

✓ PASS: Extension Extraction
  Files:      1000000
  Duration:   4.11 ms
  Throughput: 243072435.6 files/sec
  Target:     100000.0 files/sec
  Difference: +242972.4%

✓ PASS: File Categorization
  Files:      500000
  Duration:   37.99 ms
  Throughput: 13160665.4 files/sec
  Target:     50000.0 files/sec
  Difference: +26221.3%

[Additional benchmarks...]

SUMMARY: 5/5 benchmarks passed ✅
```

## Real-World Performance

### Organize Command

- **Small directories** (<100 files): <10ms
- **Medium directories** (100-1K files): 10-100ms
- **Large directories** (1K-10K files): 100-1000ms
- **Very large directories** (>10K files): 1-10 seconds

Performance scales linearly with file count.

### Analyze Command

- **Disk usage only**: ~351K files/sec
- **With content analysis**: ~500 files/sec (due to file reading)

Content analysis includes:
- Image dimensions for `.jpg`, `.png`, `.gif`
- Video duration for `.mp4`, `.avi`, `.mkv`
- Document metadata where available

### Dedupe Command

- **Hash calculation**: ~30K files/sec
- **Duplicate detection**: Depends on file sizes
  - Small files (<1MB): Very fast
  - Large files (>100MB): Limited by I/O

Hash calculation uses SHA-256 with streaming for memory efficiency.

### Watch Command

- **File event response**: <50ms
- **Check interval**: Configurable (default: 5 seconds)
- **Batch processing**: Multiple files processed efficiently

### Workspace Command

- **Project detection**: ~1K projects/sec
- **Cleanup analysis**: Depends on project size
- **File removal**: Limited by filesystem

### Archive Command

- **File selection**: ~1K files/sec
- **Archiving**: Limited by I/O and compression
- **tar.gz compression**: ~10-50 MB/sec (depends on compression level)

## Optimization Strategies

### Memory Optimization

ZigStack uses:
- **Arena allocators** for temporary operations
- **Streaming hash calculation** for large files
- **Efficient data structures** (HashMap, ArrayList)
- **Minimal allocations** in hot paths

Typical memory usage: <100MB for most operations

### I/O Optimization

- **Buffered I/O** for file reading
- **Batch operations** where possible
- **Directory iteration** without loading all entries into memory
- **Lazy evaluation** for file stats

### CPU Optimization

- **Release builds** with `-Doptimize=ReleaseFast`
- **Minimal branching** in hot loops
- **Efficient string handling** (no unnecessary copies)
- **Optimized categorization** using lookup tables

## Performance Tips

### For Maximum Speed

1. **Use ReleaseFast builds**:
   ```bash
   zig build -Doptimize=ReleaseFast
   ```

2. **Limit recursion depth**:
   ```bash
   zigstack organize --max-depth 3 /path
   ```

3. **Filter by size** for analyze:
   ```bash
   zigstack analyze --min-size 10 /path  # Only files >10MB
   ```

4. **Skip content analysis**:
   ```bash
   zigstack analyze /path  # Don't use --content flag
   ```

### For Large Directories

1. **Use appropriate strategies**:
   ```bash
   # Conservative for safety
   zigstack workspace cleanup --strategy conservative ~/Code

   # Aggressive for maximum cleanup
   zigstack workspace cleanup --strategy aggressive ~/Code
   ```

2. **Process in batches**:
   ```bash
   # Instead of one huge operation
   zigstack organize ~/Documents/2024
   zigstack organize ~/Documents/2023
   # Rather than: zigstack organize ~/Documents
   ```

3. **Use dry-run first**:
   ```bash
   # Always preview large operations
   zigstack dedupe --dry-run /large/directory
   ```

## Platform Performance

### macOS (M1/M2/M3)

- **Best overall performance** due to unified memory architecture
- **Excellent SSD performance** on Apple Silicon
- **Fast file system operations** with APFS

### Linux

- **Very good performance** on modern filesystems (ext4, btrfs, xfs)
- **SSD recommended** for best results
- **Performance varies** by distro and configuration

### Windows

- **Good performance** on NTFS
- **Slightly slower** than Unix-like systems for some operations
- **SSD strongly recommended**

## Troubleshooting Performance

### Slow Performance

1. **Check disk type**:
   - SSD: Expected fast performance
   - HDD: 10-100x slower is normal

2. **Check CPU usage**:
   ```bash
   # On macOS/Linux
   top -p $(pgrep zigstack)
   ```

3. **Use verbose mode**:
   ```bash
   zigstack <command> --verbose /path
   ```

4. **Reduce scope**:
   - Use `--max-depth` to limit recursion
   - Use `--min-size` to filter files
   - Process smaller batches

### Memory Issues

1. **Monitor memory usage**:
   ```bash
   # On macOS/Linux
   ps aux | grep zigstack
   ```

2. **Reduce batch size** for large operations

3. **Process incrementally** rather than all at once

## Future Optimizations

Potential areas for future optimization:

- [ ] Parallel file processing for multi-core systems
- [ ] Memory-mapped file I/O for large files
- [ ] Cached categorization results
- [ ] Incremental hash calculation
- [ ] GPU acceleration for content analysis

## Benchmarking Your System

To benchmark on your specific hardware:

```bash
# Clone the repository
git clone https://github.com/yourusername/zigstack
cd zigstack

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Run benchmarks
zig build benchmark

# Test with real data
time ./zig-out/bin/zigstack organize --dry-run ~/your/test/directory
```

Compare your results with the targets above to assess performance on your system.

## Contributing

If you identify performance improvements:

1. Run benchmarks before changes
2. Implement optimization
3. Run benchmarks after changes
4. Document performance improvement
5. Submit PR with benchmark results

Performance regressions will be caught in CI benchmarks.
