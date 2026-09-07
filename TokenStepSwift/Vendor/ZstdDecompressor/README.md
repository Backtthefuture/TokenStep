# Vendored Zstandard decompressor

`zstddeclib.c` is generated from the official Zstandard v1.5.7 source with:

```text
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

The source is decompression-only and is statically compiled into TokenStep and
TokenStepHelper. The Swift bridge exposes only the stable streaming decoder
functions needed for concatenated Harness frames.

Source: https://github.com/facebook/zstd/tree/v1.5.7
Generated from commit: f8745da6ff1ad1e7bab384bd1f9d742439278e99
