# Modified PRoot Source

This branch contains the modified proot source code used by Android-Proot-Builder.

## Modifications Applied

### 1. `src/extension/ashmem_memfd/ashmem_memfd.c`
- Added `#include <string.h>` at line 2
- Fixes implicit declaration errors under clang C99 mode

### 2. `src/loader/loader-info.awk`
- Replaced gawk-specific `strtonum()` function with portable `hextodec()` implementation
- Fixes build failures on systems where default awk is mawk or other non-gawk implementations

## Build Configuration
- Target Android API: 28
- Architectures: aarch64, armv7a, x86_64
- talloc: statically linked into libproot.so
- Output: libproot.so (shared object with exported main symbol)

## Usage
This source is used by Android-Proot-Builder's build-android.sh to cross-compile
proot as a shared library (libproot.so) for Android, which is then loaded by Pbox
via dlopen/dlsym.
