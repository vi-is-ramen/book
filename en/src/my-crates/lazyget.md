# Lazy Loading, Smart Caching: The `lazyget` Crate

Welcome to the `lazyget` guide! If you've ever found yourself re-downloading the same huge asset over and over,
or copy-pasting fragile caching code between projects, you're in the right place.

`lazyget` is a tiny but mighty Rust crate that solves a big problem: **how to fetch an artifact (file, binary,
dataset – anything) once, cache it locally, and never worry about it again**.

It does one thing and does it well: given a cache directory and an artifact identifier, it will either return
the existing cached path, or run your custom fetch logic exactly once, store the result, and give you back the
path – all with atomic updates and automatic cleanup on failure.

Let's dive in.

## What Problem Does `lazyget` Solve?

Imagine you're writing a CLI tool that needs a large AI model file, a game engine that downloads asset packs,
or a build script that pulls a specific toolchain. You want:

- **No redundant downloads** – if the artifact is already on disk, just use it.
- **No stale caches** – sometimes you *must* refresh the artifact.
- **No half‑written files** – if the download fails, the old (or partial) version should never be used.
- **No boilerplate** – you shouldn't have to write temp directory dances and error handling every time.

`lazyget` handles all of that for you. You just tell it *how* to fetch the artifact (a closure or async
function), and it takes care of the rest.

## Quick Start

Add `lazyget` to your `Cargo.toml`:

```shell
cargo add lazyget
```

If you need asynchronous support (using `tokio`), enable the `async` feature:

```shell
cargo add lazyget --features async
```

### Synchronous Example

```rust
use lazyget::{fetch, make_id};
use std::fs;
use std::path::Path;

// Where to store cached artifacts (here: system cache directory)
let cache_dir = dirs::cache_dir().unwrap().join("my-app");

// A stable ID for your artifact – can be based on URL and commit hash
let id = make_id("https://github.com/example/model", Some("v1.2.3"));

let artifact_path = fetch(&cache_dir, &id, |temp_dir: &Path| {
    // This closure runs only when the artifact is NOT already cached.
    // `temp_dir` is a scratch directory that will become the final cache location.
    // Download or generate your artifact here:
    let response = ureq::get("https://example.com/model.bin").call()?;
    let mut reader = response.into_reader();
    let mut file = fs::File::create(temp_dir.join("model.bin"))?;
    std::io::copy(&mut reader, &mut file)?;
    Ok(())
})?;

println!("Artifact ready at: {}", artifact_path.display());
```

If you run this twice, the closure runs only the first time. The second call immediately returns the
cached path.

### Asynchronous Example (with `tokio`)

Enable the `async` feature and use `async_fetch`:

```rust
use lazyget::async_fetch;
use tokio::fs;
use tokio::io::AsyncWriteExt;

let cache_dir = dirs::cache_dir().unwrap().join("my-app");
let id = lazyget::make_id("https://github.com/example/model", Some("v1.2.3"));

let artifact_path = async_fetch(&cache_dir, &id, |temp_dir| async move {
    let url = "https://example.com/model.bin";
    let response = reqwest::get(url).await?;
    let bytes = response.bytes().await?;
    let mut file = tokio::fs::File::create(temp_dir.join("model.bin")).await?;
    file.write_all(&bytes).await?;
    Ok(())
}).await?;
```

## Core Concepts

### 1. Artifact Identifier

Every artifact is identified by a **directory name** under your cache root. The simplest way is to use a
human-readable string:

```rust
let id = "my-cool-model-v2";
```

But you can also generate a deterministic hash from a URL and an optional tag (like a Git commit) using
`make_id`:

```rust
let id = make_id("https://github.com/example/repo", Some("abc123def"));
// => "a6b4c3e2..."  (64 hex characters)
```

`make_id` computes a SHA‑256 of `url` + `":"` + `tag` (if tag is `Some`). This is perfect when your
artifact's source changes over time and you want to invalidate the cache automatically.

### 2. `fetch` / `async_fetch` – The Lazy Workhorse

```rust
fn fetch<P, F>(cache_dir: P, artifact_id: &str, fetch_fn: F) -> Result<PathBuf>
where
    P: AsRef<Path>,
    F: FnOnce(&Path) -> Result<(), Box<dyn Error + Send + Sync>>,
```

**Behaviour**:

- Check if `cache_dir/artifact_id` exists.
- If yes -> return its path immediately.
- If no:
  - Create a temporary directory `.artifact_id-tmp` inside `cache_dir`.
  - Call `fetch_fn` with that temp directory.
  - If `fetch_fn` succeeds -> atomically rename temp dir to the final name.
  - If `fetch_fn` fails -> delete the temp directory and propagate the error.

This guarantees that you never see a partially written or corrupted artifact.

### 3. `refetch` / `async_refetch` – Force Refresh

Sometimes you want to ignore the existing cache and re‑fetch the artifact, even
if it's present. That's what `refetch` is for:

```rust
fn refetch<P, F>(cache_dir: P, artifact_id: &str, fetch_fn: F) -> Result<PathBuf>
```

It deletes the existing cached directory (if any) and then calls `fetch` internally.

## Error Handling

All fallible operations return a `Result<T, LazyGetError>`. `LazyGetError`
is a `thiserror` enum covering:

- `Io` – I/O errors (file system).
- `Fetch` – Your own closure returned an error (wrapped in a boxed trait object).
- `CacheCreate` – Failed to create the root cache directory.
- `AtomicRename` – The final rename step failed (very rare, but possible on some filesystems).

This means you can pattern‑match to handle specific cases or use `?` to bubble errors up.

```rust
use lazyget::{LazyGetError, fetch};

match fetch(cache_dir, "my-id", |dir| Ok(())) {
    Ok(path) => println!("Got {}", path.display()),
    Err(LazyGetError::Fetch(e)) => eprintln!("Download logic failed: {}", e),
    Err(e) => eprintln!("Caching system error: {}", e),
}
```

## Under the Hood: How Atomic Caching Works

`lazyget` follows a simple but robust protocol:

1. **Check existence** – If `target_dir` exists, we’re done.
2. **Prepare temp** – `cache_dir/.artifact_id-tmp`. If it already exists from a previous
interrupted run, it gets deleted.
3. **Run your fetch** – You write files into the temp directory. If you need to download
multiple files or unpack an archive, do it there.
4. **Commit** – `std::fs::rename` (or `tokio::fs::rename`). On most filesystems this is
atomic – either the rename happens or it doesn’t. No reader will ever see an incomplete directory.
5. **Cleanup** – If your closure returns an error, the temp directory is removed automatically.

This approach works on Linux, macOS, and Windows.

## Complete Example: Downloading a Zip Archive

Here’s a real‑world synchronous example that downloads a zip file, extracts it, and caches the result:

```rust,no_run
use lazyget::{fetch, make_id, LazyGetError};
use std::fs::File;
use std::io::{Cursor, Read};
use std::path::Path;
use zip::ZipArchive;

fn fetch_and_extract(temp_dir: &Path) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Download zip
    let mut resp = ureq::get("https://example.com/assets.zip").call()?;
    let mut bytes = Vec::new();
    resp.into_reader().read_to_end(&mut bytes)?;

    // Unzip into temp_dir
    let mut archive = ZipArchive::new(Cursor::new(bytes))?;
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let out_path = temp_dir.join(file.mangled_name());
        if file.is_dir() {
            std::fs::create_dir_all(&out_path)?;
        } else {
            let mut outfile = File::create(&out_path)?;
            std::io::copy(&mut file, &mut outfile)?;
        }
    }
    Ok(())
}

let cache_dir = std::env::temp_dir().join("my-cache");
let id = make_id("https://example.com/assets.zip", Some("v2"));
let path = fetch(&cache_dir, &id, fetch_and_extract)?;
println!("Assets ready at: {}", path.display());
```

## Testing Strategies

`lazyget` is easy to test because you can provide any `FnOnce` – including one that counts
how many times it was called. The crate itself uses `tempfile::tempdir()` to
create temporary cache roots for tests.

Example test pattern:

```rust
#[test]
fn test_caching_behaviour() {
    let tmp = tempfile::tempdir().unwrap();
    let id = "test-id";
    let mut counter = 0;

    // First call: runs closure
    let _ = fetch(tmp.path(), id, |_dir| { counter += 1; Ok(()) }).unwrap();
    assert_eq!(counter, 1);

    // Second call: uses cache
    let _ = fetch(tmp.path(), id, |_dir| { counter += 1; Ok(()) }).unwrap();
    assert_eq!(counter, 1);
}
```

## Feature Flags

- **default** – no extra features.
- **async** – enables the `tokio` dependency and provides `async_fetch` / `async_refetch`.
You get `tokio::fs` and `tokio::process`, but the runtime is not started automatically –
you need a Tokio runtime in your application.

## When Not to Use `lazyget`

- You need to cache very large numbers of tiny files (the per‑artifact directory overhead
is minimal, but if you have millions, consider a database).
- You are writing a `no_std` environment (this crate uses `std` heavily).

## Conclusion

`lazyget` gives you bulletproof, atomic, lazy caching with an API that fits in your head.
It’s the kind of crate that disappears into your code – you only notice it when it works perfectly.

Go ahead, stop re‑downloading that 2 GB model file on every CI run, and let `lazyget` take the wheel.

*Happy lazy fetching!*

## Links

[crates.io](https://crates.io/lazyget)
[docs.rs](https://docs.rs/lazyget)
