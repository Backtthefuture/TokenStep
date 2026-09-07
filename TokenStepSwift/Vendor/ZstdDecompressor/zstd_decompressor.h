#ifndef TOKENSTEP_ZSTD_DECOMPRESSOR_H
#define TOKENSTEP_ZSTD_DECOMPRESSOR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZSTD_DCtx_s ZSTD_DCtx;
typedef ZSTD_DCtx ZSTD_DStream;

typedef struct {
    const void *src;
    size_t size;
    size_t pos;
} ZSTD_inBuffer;

typedef struct {
    void *dst;
    size_t size;
    size_t pos;
} ZSTD_outBuffer;

ZSTD_DStream *ZSTD_createDStream(void);
size_t ZSTD_freeDStream(ZSTD_DStream *zds);
size_t ZSTD_initDStream(ZSTD_DStream *zds);
size_t ZSTD_decompressStream(ZSTD_DStream *zds, ZSTD_outBuffer *output, ZSTD_inBuffer *input);
size_t ZSTD_DStreamInSize(void);
size_t ZSTD_DStreamOutSize(void);
unsigned ZSTD_isError(size_t code);
const char *ZSTD_getErrorName(size_t code);

#ifdef __cplusplus
}
#endif

#endif
