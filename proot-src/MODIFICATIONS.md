# Modifications from upstream termux/proot v5.1.107.92

This is the proot source tree used by Android-Proot-Builder. It includes:

1. **extension/ashmem_memfd/ashmem_memfd.c**: Added `#include <string.h>` for
   `memset`/`memcpy` prototypes on strict toolchains.

2. **loader/loader-info.awk**: Replaced gawk-only `strtonum()` with a portable
   `hextodec()` function so the script works with mawk/busybox awk.

3. **src/CMakeLists.txt**: New CMake build system replacing GNUmakefile.
   Produces `libproot.so` (dlopenable shared library) with loader embedded
   and talloc statically linked.

4. **vendor/talloc/**: Vendored talloc 2.4.2 (single-file amalgamation) for
   static linking into libproot.so.
