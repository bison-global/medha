// Medha's small C API over llama.cpp.
//
// The Dart side talks only to these functions, so llama.cpp API changes stay
// contained in medha_llama.c. Every function is called from one background
// Dart isolate per loaded model; none of them are thread-safe across contexts
// shared between isolates.

#ifndef MEDHA_LLAMA_H
#define MEDHA_LLAMA_H

#include <stdint.h>

#if defined(_WIN32)
#define MEDHA_API __declspec(dllexport)
#else
#define MEDHA_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct medha_ctx medha_ctx;

// Loads a GGUF model and creates an inference context.
// n_gpu_layers: -1 = offload all layers (Metal on iOS), 0 = CPU only.
// Returns NULL on failure; see medha_last_error().
MEDHA_API medha_ctx * medha_load(const char * path, int32_t n_ctx, int32_t n_threads, int32_t n_gpu_layers);

MEDHA_API void medha_free(medha_ctx * ctx);

// Formats a conversation with the model's built-in chat template.
// Returns the number of bytes needed (may exceed buf_len: grow and retry),
// or -1 when the model has no template llama.cpp can apply without Jinja.
MEDHA_API int32_t medha_format_chat(
    medha_ctx * ctx,
    const char ** roles,
    const char ** contents,
    int32_t n_messages,
    int32_t add_assistant,
    char * buf,
    int32_t buf_len);

// Starts a new generation from a fully formatted prompt.
// temperature <= 0 selects greedy decoding.
// Returns 0 on success, a negative code on failure.
MEDHA_API int32_t medha_begin(
    medha_ctx * ctx,
    const char * prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    float presence_penalty,
    uint32_t seed);

// Produces the next token's bytes (UTF-8, possibly a partial character).
// Returns > 0: bytes written; 0: generation finished (end of turn or context
// full); < 0: error.
MEDHA_API int32_t medha_next(medha_ctx * ctx, char * buf, int32_t buf_len);

// Number of prompt tokens the last medha_begin() consumed.
MEDHA_API int32_t medha_prompt_tokens(medha_ctx * ctx);

// Applies a LoRA adapter (a subject add-on) at [scale], replacing any
// previous one. Pass path = NULL to remove adapters. Returns 0 on success.
MEDHA_API int32_t medha_set_lora(medha_ctx * ctx, const char * path, float scale);

// Loads an embedding model (pooled sentence embeddings).
MEDHA_API medha_ctx * medha_load_embedder(const char * path, int32_t n_ctx, int32_t n_threads, int32_t n_gpu_layers);

// Embedding width of a model loaded with medha_load_embedder().
MEDHA_API int32_t medha_embedding_size(medha_ctx * ctx);

// Embeds [text] into [out] (capacity [out_len] floats). Text longer than the
// context is truncated. Returns the number of floats written, or < 0.
MEDHA_API int32_t medha_embed(medha_ctx * ctx, const char * text, float * out, int32_t out_len);

// Last error message for this thread, or "" if none.
MEDHA_API const char * medha_last_error(void);

#ifdef __cplusplus
}
#endif

#endif  // MEDHA_LLAMA_H
