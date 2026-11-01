// Implementation of medha_llama.h on top of llama.cpp.
// Pinned llama.cpp commit: see native/llama.cpp (git submodule).

#include "medha_llama.h"

#if __has_include(<llama/llama.h>)
#include <llama/llama.h>
#else
#include "llama.h"
#endif

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MEDHA_ERR_ARGS -1
#define MEDHA_ERR_TOKENIZE -2
#define MEDHA_ERR_CONTEXT_FULL -3
#define MEDHA_ERR_DECODE -4
#define MEDHA_ERR_PIECE -5

struct medha_ctx {
    struct llama_model * model;
    struct llama_context * lctx;
    const struct llama_vocab * vocab;
    struct llama_sampler * sampler;
    int32_t n_ctx;
    int32_t n_batch;
    int32_t n_used;
    int32_t prompt_tokens;
    llama_token last;
    bool done;
};

static _Thread_local char g_error[256];
static bool g_backend_ready = false;

static void set_error(const char * msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

const char * medha_last_error(void) {
    return g_error;
}

medha_ctx * medha_load(const char * path, int32_t n_ctx, int32_t n_threads, int32_t n_gpu_layers) {
    g_error[0] = '\0';
    if (path == NULL || n_ctx <= 0) {
        set_error("invalid arguments");
        return NULL;
    }
    if (!g_backend_ready) {
        llama_backend_init();
        g_backend_ready = true;
    }

    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = n_gpu_layers;
    struct llama_model * model = llama_model_load_from_file(path, mp);
    if (model == NULL) {
        set_error("could not load model file");
        return NULL;
    }

    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = (uint32_t) n_ctx;
    cp.n_batch = 512;
    cp.n_threads = n_threads > 0 ? n_threads : 4;
    cp.n_threads_batch = cp.n_threads;
    cp.no_perf = true;
    struct llama_context * lctx = llama_init_from_model(model, cp);
    if (lctx == NULL) {
        llama_model_free(model);
        set_error("could not create context");
        return NULL;
    }

    medha_ctx * ctx = (medha_ctx *) calloc(1, sizeof(medha_ctx));
    if (ctx == NULL) {
        llama_free(lctx);
        llama_model_free(model);
        set_error("out of memory");
        return NULL;
    }
    ctx->model = model;
    ctx->lctx = lctx;
    ctx->vocab = llama_model_get_vocab(model);
    ctx->n_ctx = n_ctx;
    ctx->n_batch = (int32_t) cp.n_batch;
    ctx->done = true;
    return ctx;
}

void medha_free(medha_ctx * ctx) {
    if (ctx == NULL) return;
    if (ctx->sampler != NULL) llama_sampler_free(ctx->sampler);
    if (ctx->lctx != NULL) llama_free(ctx->lctx);
    if (ctx->model != NULL) llama_model_free(ctx->model);
    free(ctx);
}

int32_t medha_format_chat(
    medha_ctx * ctx,
    const char ** roles,
    const char ** contents,
    int32_t n_messages,
    int32_t add_assistant,
    char * buf,
    int32_t buf_len) {
    if (ctx == NULL || roles == NULL || contents == NULL || n_messages <= 0) return -1;
    const char * tmpl = llama_model_chat_template(ctx->model, NULL);
    if (tmpl == NULL) return -1;

    llama_chat_message * msgs = (llama_chat_message *) calloc((size_t) n_messages, sizeof(llama_chat_message));
    if (msgs == NULL) return -1;
    for (int32_t i = 0; i < n_messages; i++) {
        msgs[i].role = roles[i];
        msgs[i].content = contents[i];
    }
    int32_t n = llama_chat_apply_template(tmpl, msgs, (size_t) n_messages, add_assistant != 0, buf, buf_len);
    free(msgs);
    return n < 0 ? -1 : n;
}

static struct llama_sampler * make_sampler(
    const struct llama_vocab * vocab,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    float presence_penalty,
    uint32_t seed) {
    struct llama_sampler_chain_params sp = llama_sampler_chain_default_params();
    sp.no_perf = true;
    struct llama_sampler * chain = llama_sampler_chain_init(sp);

    if (temperature <= 0.0f) {
        llama_sampler_chain_add(chain, llama_sampler_init_greedy());
        return chain;
    }
    if (top_k > 0) llama_sampler_chain_add(chain, llama_sampler_init_top_k(top_k));
    if (presence_penalty != 0.0f) {
        llama_sampler_chain_add(
            chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.0f, 0.0f, presence_penalty));
    }
    if (top_p > 0.0f && top_p < 1.0f) llama_sampler_chain_add(chain, llama_sampler_init_top_p(top_p, 1));
    if (min_p > 0.0f) llama_sampler_chain_add(chain, llama_sampler_init_min_p(min_p, 1));
    llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(chain, llama_sampler_init_dist(seed));
    return chain;
}

int32_t medha_begin(
    medha_ctx * ctx,
    const char * prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    float min_p,
    float presence_penalty,
    uint32_t seed) {
    g_error[0] = '\0';
    if (ctx == NULL || prompt == NULL) {
        set_error("invalid arguments");
        return MEDHA_ERR_ARGS;
    }

    // Each generation starts from a clean cache; the caller sends the whole
    // (already truncated) conversation every time.
    llama_memory_clear(llama_get_memory(ctx->lctx), true);
    ctx->n_used = 0;
    ctx->prompt_tokens = 0;
    ctx->done = false;

    if (ctx->sampler != NULL) llama_sampler_free(ctx->sampler);
    ctx->sampler = make_sampler(ctx->vocab, temperature, top_p, top_k, min_p, presence_penalty, seed);

    const int32_t text_len = (int32_t) strlen(prompt);
    const int32_t needed = -llama_tokenize(ctx->vocab, prompt, text_len, NULL, 0, true, true);
    if (needed <= 0) {
        set_error("tokenizer failed");
        ctx->done = true;
        return MEDHA_ERR_TOKENIZE;
    }
    if (needed >= ctx->n_ctx) {
        set_error("prompt is longer than the context window");
        ctx->done = true;
        return MEDHA_ERR_CONTEXT_FULL;
    }

    llama_token * tokens = (llama_token *) malloc(sizeof(llama_token) * (size_t) needed);
    if (tokens == NULL) {
        set_error("out of memory");
        ctx->done = true;
        return MEDHA_ERR_ARGS;
    }
    const int32_t n = llama_tokenize(ctx->vocab, prompt, text_len, tokens, needed, true, true);
    if (n < 0) {
        free(tokens);
        set_error("tokenizer failed");
        ctx->done = true;
        return MEDHA_ERR_TOKENIZE;
    }

    for (int32_t i = 0; i < n; i += ctx->n_batch) {
        const int32_t chunk = (n - i) < ctx->n_batch ? (n - i) : ctx->n_batch;
        if (llama_decode(ctx->lctx, llama_batch_get_one(tokens + i, chunk)) != 0) {
            free(tokens);
            set_error("decode failed while reading the prompt");
            ctx->done = true;
            return MEDHA_ERR_DECODE;
        }
    }
    free(tokens);
    ctx->n_used = n;
    ctx->prompt_tokens = n;
    return 0;
}

int32_t medha_next(medha_ctx * ctx, char * buf, int32_t buf_len) {
    if (ctx == NULL || buf == NULL || buf_len <= 0) return MEDHA_ERR_ARGS;

    // A token can render to zero bytes (a hidden control token). Since 0 means
    // "finished" to the caller, keep sampling until a token has visible bytes.
    for (;;) {
        if (ctx->done) return 0;
        if (ctx->n_used >= ctx->n_ctx) {
            ctx->done = true;
            return 0;
        }

        const llama_token token = llama_sampler_sample(ctx->sampler, ctx->lctx, -1);
        if (llama_vocab_is_eog(ctx->vocab, token)) {
            ctx->done = true;
            return 0;
        }

        const int32_t n = llama_token_to_piece(ctx->vocab, token, buf, buf_len, 0, false);
        if (n < 0) {
            set_error("token does not fit the output buffer");
            ctx->done = true;
            return MEDHA_ERR_PIECE;
        }

        ctx->last = token;
        if (llama_decode(ctx->lctx, llama_batch_get_one(&ctx->last, 1)) != 0) {
            set_error("decode failed");
            ctx->done = true;
            return MEDHA_ERR_DECODE;
        }
        ctx->n_used += 1;

        if (n > 0) return n;
    }
}

int32_t medha_prompt_tokens(medha_ctx * ctx) {
    return ctx == NULL ? 0 : ctx->prompt_tokens;
}
