# Kissreplace: A Minimalist Template Engine

Welcome to **kissreplace** – a tiny, no‑nonsense template engine that lives by the **KISS** (Keep It Simple, Stupid!) principle.  
If you need to replace placeholders like `@VAR@` in strings, file paths, or whole collections, this crate does exactly that and
nothing more. No complex DSLs, no runtime overhead you didn’t ask for - just plain, predictable substitution.

---

## What it does?

- Finds every occurrence of `@VAR@` in a string, where `VAR` follows a **simple naming rule** (letters, digits, underscore, and
must start with a letter or underscore).
- Replaces it with a value from a hash map (`HashMap<String, String>`).
- Leaves invalid or missing variables untouched (e.g. `@123@`, `@var-name@` or `@UNKNOWN@` stay as they are).
- Works on single strings, whole vectors (in‑place or by value), and file paths.

---

## Add to your project

```shell
cargo add kissreplace
```

Optional async support (enables `tokio` as a dependency, useful when you need async I/O around replacement):

```toml
cargo add kissreplace --features async
```

---

## Quick start

```rust
use std::collections::HashMap;
use kissreplace::{KissReplace, Variables};

let mut vars = Variables::new();
vars.insert("NAME".to_string(), "World".to_string());
vars.insert("PROJECT".to_string(), "kissreplace".to_string());

let template = "Hello @NAME@, you're reading @PROJECT@ docs!";
let result = vars.replace_str(template);
println!("{}", result);
// Output: Hello World, you're reading kissreplace docs!
```

Under the hood `Variables` is just a type alias for `HashMap<String, String>`, so you can build it any way you like.

---

## How replacement works

The function `replace_str` scans the input **from left to right**:

1. Look for the next `'@'`.
2. From that position, search forward for a closing `'@'`.
3. Check if the text between them is a **valid variable name**.
4. If yes – replace it with the value from the map (or leave `@VAR@` if missing).
5. If not – treat the first `'@'` as a literal character and continue scanning.

Because the scan is **single‑pass** and no recursive expansion is performed, nested‑looking variables
like `@A@` where `A` maps to `"@B@"` are **not** expanded further – you get exactly one substitution per placeholder.

### Valid variable names

- Must not be empty.
- First character must be an ASCII letter (`a-z`, `A-Z`) or underscore `_`.
- Following characters can be ASCII letters, digits (`0-9`), or underscore.

```rust
use kissreplace::valid::is_valid_var_name;

assert!(is_valid_var_name("PROJECT_2"));
assert!(is_valid_var_name("_private"));
assert!(!is_valid_var_name("123start"));
assert!(!is_valid_var_name("with-dash"));
```

---

## The `KissReplace` trait

This trait is implemented for `Variables` (`HashMap<String, String>`) and gives you several convenience methods:

| Method | Description |
|--------|-------------|
| `replace_str(&self, input: &str) -> String` | Core method – replaces placeholders in a single string. |
| `replace(&self, sources: Vec<String>) -> Vec<String>` | Apply to every element of a vector, returning a new vector. |
| `replace_mut(&self, sources: &mut Vec<String>)` | **In‑place** version – more allocation‑efficient. |
| `replace_paths(&self, paths: Vec<PathBuf>) -> Vec<PathBuf>` | Works on file paths (converts to string, replaces, then back to `PathBuf`). |

### Example: replacing many strings

```rust
let vars = /* ... */;
let mut lines = vec![
    "name = @NAME@".to_string(),
    "version = @VERSION@".to_string(),
];
vars.replace_mut(&mut lines);
// lines now contains the replaced values
```

### Example: file paths

```rust
let vars = /* ... */;
let paths = vec![
    PathBuf::from("src/@PROJECT@/main.rs"),
    PathBuf::from("config/@PROJECT@.toml"),
];
let new_paths = vars.replace_paths(paths);
```

---

## Scanning for variables

If you only need to know **which variables** appear in a template (without replacing them), use `scan::extract_vars`:

```rust
use kissreplace::scan;

let template = "Hello @NAME@, your @PROJECT@ is version @VERSION@";
let vars = extract_vars(template);
// vars = {"NAME", "PROJECT", "VERSION"}
```

It returns a `HashSet<String>` of unique, valid variable names found. The scanning logic is exactly the same as in `replace_str`, so you can trust that the reported names would be replaced when you later call `replace_str`.

---

## Error handling

The crate defines its own `KissReplaceError` enum. Currently two variants exist:

- `InvalidVariableName(String)` – returned by functions that validate names (if you build your own validation logic).
- `InvalidUtf8` – used when converting a `PathBuf` to a string fails (the path is not valid UTF‑8).

Most replacement methods are infallible (they don’t return `Result`). Errors only appear if you explicitly call into the `valid` module or handle paths with non‑UTF‑8 components.

```rust
use kissreplace::{KissReplaceError, valid};

if let Err(e) = some_validation_function("1invalid") {
    println!("Error: {}", e);
}
```

---

## Async feature

When you enable the `async` feature, the crate pulls in `tokio` as an optional dependency. The replacement logic itself is **synchronous** – this feature simply makes `tokio` available for your own async I/O tasks, for example:

- Reading hundreds of template files concurrently with `tokio::fs`.
- Replacing variables in each file, then writing the results.

Nothing in `kissreplace` is `async` by itself, but the feature lets you keep your dependency list tidy if you’re already using `tokio`.

---

## Testing & edge cases

The crate comes with a thorough test suite. Here are some behaviours you can rely on:

| Input | Variables | Output |
|-------|-----------|--------|
| `"@NAME@ and @MISSING@"` | `NAME=Alice` | `"Alice and @MISSING@"` |
| `"@@X@@"` | `X=Y` | `"@Y@"` |
| `"@var-name@ and @123@"` | – | unchanged (invalid names) |
| `"hello @X and @X@"` | `X=Y` | `"hello @X and Y"` (unclosed `@` left as literal) |
| `"@A@@B@"` | `A=1, B=2` | `"12"` |
| `"@A@"` | `A="@B@"`, `B=X` | `"@B@"` (no nested expansion) |

The **no‑nested‑expansion** rule is intentional – it keeps complexity low and avoids infinite loops.

---

## Performance considerations

- **Single pass** over the input – `O(n)` time.
- `replace_mut` reuses the existing `Vec` capacity, reducing allocations when you process many strings.
- The scanner for `extract_vars` also performs a single pass and uses a `HashSet` to store unique names.

If you need to replace the same template hundreds of times with different variable sets, consider pre‑scanning for variable names and then doing replacements via `String::replace` or a manual loop – but for most use cases, calling `replace_str` directly is perfectly fine.

---

## Philosophy – why KISS?

Many template engines grow organically: conditionals, loops, filters, partials... and suddenly your “simple” templating is a full‑blown language. **kissreplace** deliberately stops at placeholder substitution. It’s ideal for:

- Configuration file generation (e.g. `config.@ENV@.toml` -> `config.production.toml`)
- Simple email or notification templates
- Environment variable expansion in custom CLIs
- Teaching the concept of templating without distractions

If you need logic, you can always combine it with Rust’s own control flow – that keeps both the template syntax and your code simple.

---

## Summary

| What you want | How kissreplace helps |
|---------------|----------------------|
| Replace `@VAR@` placeholders | `vars.replace_str("...")` |
| Process many strings efficiently | `replace_mut(&mut vec)` |
| Work with file paths | `replace_paths(vec![...])` |
| Discover which variables are used | `scan::extract_vars("...")` |
| Validate variable names | `valid::is_valid_var_name("...")` |
| Stay dependency‑light | Only uses `std` + `thiserror` (async optional) |

**kissreplace** is a small, focused tool – and that’s its superpower. Go ahead, sprinkle some `@VAR@` placeholders into your strings, and let this crate do the rest. Happy templating!

## Links

[crates.io](https://crates.io/kissreplace)
[docs.rs](https://docs.rs/kissreplace)
