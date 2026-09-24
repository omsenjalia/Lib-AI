# Patching fllama to one slot

Written down because the arithmetic is easy to lose: today the app requests a
context and a conversation receives a quarter of it. See
[ARCHITECTURE.md § 3.1.1](../ARCHITECTURE.md) for the sources, and
`AppConstants.perChatContextLength` for the code that has to agree with whatever
the engine does.

## Why

The pinned fllama build runs every context with four llama.cpp sequences
(`ServerManager::DEFAULT_N_PARALLEL = 4` in `fllama_inference_queue.h`), and the
Dart request's `nParallel` field is web-only. Because fllama also leaves
`kv_unified` at its `false` default, llama.cpp splits the requested context
across those sequences: `n_ctx_seq = n_ctx / n_seq_max`. A request for 8192
tokens gives each conversation 2048, while the KV cache is allocated for the
whole 8192.

One conversation at a time is all this app ever runs - generation is serialised
behind `_activeRequestId`, and loads behind `_loadInFlight`. The other three
slots cost a quarter of the window each and buy nothing.

## The patch

Against `Telosnex/fllama` at `f624e4bfaf6c354d557ddc841ae4990760819c4a`:

```diff
--- a/src/fllama_inference_queue.h
+++ b/src/fllama_inference_queue.h
@@
-  static constexpr int DEFAULT_N_PARALLEL = 4;
+  static constexpr int DEFAULT_N_PARALLEL = 1;
```

`n_parallel` is not part of the `ServerResources` cache key (`n_ctx`,
`n_gpu_layers`, mmproj and draft paths are), so the patched engine has to serve
every request in the process - a cached context built by an unpatched build would
be reused as-is. That is the normal case here: one process, one engine.

## Applying it

1. Fork `Telosnex/fllama` and apply the diff at the pinned commit.
2. Point `pubspec.yaml` at the fork, keeping the `ref` form:

   ```yaml
   fllama:
     git:
       url: https://github.com/<you>/fllama.git
       ref: <commit sha of the patched commit>
   ```

3. Set `AppConstants.parallelSlots` to `1` in the same change. With that one
   line edited, `perChatContextLength` returns the requested total and every
   prompt budget, the loader preflight and the context meter follow automatically.
4. Rebuild and check one real conversation: ask for a long answer and confirm the
   context meter reaches the requested figure instead of stopping at a quarter of
   it.

## What it does not change

- Memory: the KV cache is `n_ctx_seq * n_seq_max` either way, so the total is
  unchanged. One stream of `n_ctx` tokens replaces four of `n_ctx / 4`.
- GPU: still CPU-only on Android. fllama's CMake enables Vulkan only on Windows.
  If GPU offload matters more than anything else here, that is a build-project
  question, not a configuration one - a React Native build on `llama.rn` ships an
  OpenCL backend for Adreno 700+ (Q4_0 / Q6_K only) and exposes `n_parallel` and
  `kv_unified` at context init, at the cost of re-implementing the UI.
