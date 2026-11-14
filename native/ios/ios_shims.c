// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
// iOS has no __clear_cache symbol to link against. It is only referenced by RandomX's ARM64 JIT (mining/PoW
// hashing), which the wallet never runs and iOS would not allow anyway. Implemented with Apple's equivalent so the
// reference resolves correctly rather than to a stub.
#include <libkern/OSCacheControl.h>
#include <stddef.h>

void __clear_cache(void *start, void *end) {
  sys_icache_invalidate(start, (size_t)((char *)end - (char *)start));
}
