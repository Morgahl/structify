# TODOS

- Add a STRICT version of `convert` that fails with KeyError if any keys are present in the input that are not in the target struct, rather than filtering out extra keys like in convert. (Strict keyset enforcement)

- Look into turning these into macros that fallback onto the runtime implementations BUT:

  - IF the AST can be parsed well enough from the call site let's go ahead and straight up do direct hard bindings out of and into the expected structures with fallbacks on defaults
  - (BONUS) (exact equal keyset) we can optimize this at comp time to be a put to `:__struct__`
