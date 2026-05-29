# `wrapc`: Parsing `rustc` Arguments for `RUSTC_WRAPPER` Tools

## Overview

When you build a tool that intercepts Rust compilation — be it a compilation cache, a custom profiler,
a static analyzer, or a linker-flag injector — you inevitably need to parse `rustc`'s command-line arguments.

This is harder than it sounds.

`rustc`'s CLI is a moving target: it mixes `=` and space-separated values, embeds complex sub-syntaxes
for linking (`-l static:+bundle,+whole-archive=name:renamed`), and evolves constantly with nightly-only
flags. General-purpose CLI parsers like `clap` are too rigid, too heavy, and fundamentally mismatched
for the wrapper protocol.

`wrapc` exists to solve exactly this problem.

It provides a **strongly-typed, protocol-aware parser** that:

- Understands Cargo's `<wrapper> - <rustc> <args...>` invocation format
- Parses complex flags into structured Rust types (`--emit`, `--extern`, `-L`, `-l`, etc.)
- Guarantees **flawless round-trip reconstruction** via `Info::to_args()`
- Handles unknown/nightly flags gracefully by bucketing them into `info.unknown`
- Avoids panics on edge cases like the `-` separator or missing values

In short: `wrapc` lets you focus on what your wrapper *does*, not on fighting argument parsing.

## Quick Start

Add the dependency:

```bash
cargo add wrapc
```

Then, in your wrapper's `main.rs`:

```rust
use std::process::Command;
use wrapc::fetch;

fn main() {
    // 1. Parse `std::env::args()` according to the wrapper protocol
    let mut info = fetch().expect("Failed to parse rustc arguments");

    // 2. Handle passthrough commands early (help/version/sysroot probes)
    if info.help || info.version || info.print.is_some() {
        let rustc = info.rustc.unwrap_or_else(|| "rustc".to_string());
        let status = Command::new(rustc)
            .args(info.to_args())
            .status()
            .expect("Failed to spawn rustc");
        std::process::exit(status.code().unwrap_or(1));
    }

    // 3. Inspect or mutate the compilation context
    if info.crate_name.as_deref() == Some("legacy_crate") {
        info.codegen_opts.push("opt-level=1".to_string());
    }

    // 4. Resolve the real rustc path and reconstruct arguments
    let rustc_path = info.rustc.unwrap_or_else(|| "rustc".to_string());
    let args = info.to_args();

    // 5. Execute the actual compiler
    let status = Command::new(rustc_path)
        .args(&args)
        .status()
        .expect("Failed to spawn rustc");

    std::process::exit(status.code().unwrap_or(1));
}
```

That's the entire skeleton. Five clear steps. No string splitting, no fragile indexing, zero data loss.

## Core Concepts

### The Wrapper Protocol and the `-` Separator

Cargo invokes wrappers using a strict format:

```
<wrapper_binary> - <actual_rustc_path> <rustc_args...>
```

`wrapc::fetch()` automatically:

1. Strips the first three arguments
2. Stores the real compiler path in `info.rustc`
3. Parses the remainder as `rustc` arguments

#### The `-` Edge Case

Tools sometimes pass `-` as an input filename to tell `rustc` to read from `stdin`.
Because the wrapper protocol *also* uses `-` as a separator, naive parsers break here.

`wrapc` handles this contextually:

```rust
// Invocation: `my_wrapper - rustc -`
let info = wrapc::fetch().unwrap();
assert_eq!(info.rustc, Some("rustc".to_string()));
assert_eq!(info.inputs, vec![std::path::PathBuf::from("-")]);
```

The first `-` is the protocol separator; the second is correctly identified as an input file.

### Type-Safe Flag Parsing

Instead of returning a `Vec<String>`, `wrapc` decomposes complex flags into structured types:

| Flag | Parsed Field | Type |
|------|-------------|------|
| `--emit=llvm-ir,obj` | `info.emit` | `Vec<EmitKind>` |
| `--extern crate=path` | `info.externs` | `Vec<Extern>` |
| `-L kind=path` | `info.libpaths` | `Vec<LibrarySearchPath>` |
| `-l kind:+mods=name:rename` | `info.links` | `Vec<LinkLib>` |

This lets you write logic like:

```rust
use wrapc::{LibrarySearchPathKind, LinkLibKind};

for lib_path in &info.libpaths {
    if lib_path.kind == LibrarySearchPathKind::Native {
        println!("Native search path: {:?}", lib_path.path);
    }
}

for link in &info.links {
    if matches!(link.kind, Some(LinkLibKind::Static)) {
        println!("Static lib: {} (mods: {:?})", link.name, link.modifiers);
    }
}
```

No regexes. No manual splitting. Just typed data.

### Flawless Round-Tripping

A wrapper must never corrupt the build. When you mutate a subset of arguments,
everything else must pass through *exactly* as Cargo intended.

`wrapc` guarantees this via `Info::to_args()`:

- Preserves original spacing and `=` vs. space-separated forms
- Maintains argument order
- Re-emits unrecognized flags from `info.unknown` unchanged
- Handles edge cases like quoted values or embedded spaces

You mutate what you need; `wrapc` handles the rest.

### Graceful Degradation for Nightly Flags

Rust evolves. Nightly compilers introduce new flags daily.

`wrapc` doesn't pretend to know them all. Instead:

1. Known flags -> parsed into typed fields
2. Unknown flags -> stored in `info.unknown` as raw strings
3. On `to_args()` -> all flags re-emitted exactly as received

Your wrapper won't crash on a new nightly, and you won't silently drop experimental flags.

## API Highlights

### `fetch() -> Result<Info, ParseError>`

The entry point. Reads `std::env::args()`, parses according to the wrapper protocol,
and returns a strongly-typed `Info` struct.

### `Info` Struct (selected fields)

```rust
pub struct Info {
    // Protocol metadata
    pub rustc: Option<String>,        // Path to real rustc, if provided
    
    // Common flags
    pub crate_name: Option<String>,
    pub edition: Option<String>,
    pub target: Option<String>,
    pub profile: Option<String>,      // "debug" or "release"
    
    // Action flags
    pub help: bool,
    pub version: bool,
    pub print: Option<String>,        // --print=<kind>
    
    // Compilation units
    pub inputs: Vec<PathBuf>,         // Source files
    pub emit: Vec<EmitKind>,          // --emit=...
    pub out_dir: Option<PathBuf>,
    
    // Dependency management
    pub externs: Vec<Extern>,         // --extern crate=path
    pub libpaths: Vec<LibrarySearchPath>, // -L kind=path
    pub links: Vec<LinkLib>,          // -l kind:+mods=name:rename
    
    // Code generation and diagnostics
    pub codegen_opts: Vec<String>,    // -C flag values
    pub cfg: Vec<String>,             // --cfg values
    pub features: Vec<String>,        // --cfg feature=...
    
    // Catch-all for unknown/nightly flags
    pub unknown: Vec<String>,
}
```

### `Info::to_args(&self) -> Vec<String>`

Reconstructs the original argument list with zero data loss. Use this when forwarding to the real `rustc`.

### `ParseError`

A lightweight error type that indicates *why* parsing failed (e.g., missing value, malformed flag).
Most wrapper tools can safely `.expect()` on `fetch()` since Cargo guarantees well-formed
invocations — but the error is there if you need it.

## Advanced: Mutating Compilation Context

Because `Info` owns its data, you can safely mutate fields before reconstruction:

```rust
// Force a specific codegen option for all crates
info.codegen_opts.push("target-cpu=native".to_string());

// Inject a cfg flag conditionally
if info.profile.as_deref() == Some("release") {
    info.cfg.push("feature=\"optimised\"".to_string());
}

// Replace an extern dependency path
for ext in &mut info.externs {
    if ext.name == "legacy_dep" {
        ext.path = PathBuf::from("/new/path/liblegacy_dep.rlib");
    }
}
```

All changes are reflected in `to_args()` output.

## Testing Your Wrapper

You don't need to publish or install globally to test. Use `RUSTC_WRAPPER`:

```bash
# Build your wrapper
cargo build --release

# Point Cargo to your binary
export RUSTC_WRAPPER="$(pwd)/target/release/my_wrapper"

# Run any cargo command — your wrapper will intercept rustc calls
cargo build
```

> **Pro tip**: Always check `info.help`, `info.version`, and `info.print` early in your `main()`. If any are set, forward arguments to `rustc` immediately and exit. This prevents your wrapper from interfering with Cargo's internal compiler probes.

## When to Use `wrapc`

**Ideal for**:
- Compilation caches (`sccache`-like tools)
- Build-time telemetry or profiling
- Static analysis wrappers
- Linker-flag or environment injectors
- Any tool implementing `RUSTC_WRAPPER`

**Not intended for**:
- General-purpose CLI parsing (use `clap`, `bpaf`, or `argh`)
- `rustc` driver plugins (use `rustc_driver` APIs)
- Parsing `cargo` arguments (use `cargo_metadata` or dedicated parsers)

## Links

[crates.io](https://crates.io/wrapc)
[docs.rs](https://docs.rs/wrapc)
