# The Engine Behind Inherit Templates: inherit-core

Welcome to the core library that powers [`Inherit`](https://crates.io/crates/cargo-inherit)!
If you’ve ever wished for a simple, Git‑friendly way to stamp out project templates with
dynamic placeholders, you’re in the right place. `inherit-core` does all the heavy lifting:
scanning files, replacing variables, respecting `.inherignore` rules, and even running
post‑creation hooks.

In this chapter we’ll explore the library’s design, how to use it programmatically, and peek
under the hood at its main components.

## What Problem Does It Solve?

Copy‑pasting a template project leads to stale copies, inconsistent naming, and tedious
search‑and‑replace. A better approach:

- Keep a **source template** with placeholders like `@PROJECT_NAME@`.
- Let the tool **scan** the template to discover which variables are needed.
- Ask the user (or a script) for concrete values.
- **Generate** a new project with all placeholders replaced – including file names and
folder names!

`inherit-core` implements exactly that pipeline, while being completely agnostic about the
user interface. The CLI tool `cargo-inherit` uses it to ask questions interactively, but
you could also drive it from a build script or a GUI.

## Core Concepts

| Concept | Description |
|---------|-------------|
| **Template** | A directory containing an `Inherit.toml` manifest and arbitrary files with `@VAR@` placeholders. |
| **Manifest** | TOML file that declares variables (with descriptions) and optional hooks. |
| **Placeholder syntax** | `@UPPER_SNAKE_CASE@` – powered by the [`kissreplace`] crate. |
| **`.inherignore`** | Git‑ignore style file to exclude certain paths from processing. |
| **Post‑create hooks** | Shell commands (sh or cmd) run after the project is materialised. |

> **Note:** `inherit-core` does **not** prompt the user for missing variables. That’s the
> caller’sresponsibility. The library only validates that all required variables are
> supplied and non‑empty.

## A Bird’s‑Eye View of the Pipeline

```
+-------------+        +---------------------+        +--------------+
|  Template   |------->│    load_template    |------->|   Context    |
|  Directory  |        │  (scan + manifest)  |        | (vars + desc)|
+-------------+        +---------------------+        +------+-------+
                                                             |
                                                             V
+--------------+       +------------------+           +--------------+
| Final Values |------>| process_template |---------->|  New Project |
| (Variables)  |       |  (replace, copy) |           |  Directory   |
+--------------+       +------------------+           +--------------+
```

1. **Load** – Read `Inherit.toml` and scan all template files to collect every `@VAR@` occurrence.
2. **Prompt** (outside the crate) – The caller collects concrete values from the user.
3. **Process** – Copy every file/folder, replacing placeholders in **content** and
**path names**, respecting `.inherignore`.
4. **Finalise** – Optionally run `git init` and execute `post_create` hooks.

## The Modules in Detail

### `error.rs` – Clear, actionable errors

All fallible operations return `Result<T, InheritError>`. The error enum distinguishes between:

- Missing manifest (`ManifestNotFound`)
- Parse failures (`ManifestParse`)
- Missing variables (`MissingVariables`)
- IO and command failures

```rust,ignore
pub enum InheritError {
    Io(#[from] std::io::Error),
    ManifestNotFound(PathBuf),
    ManifestParse(#[from] toml::de::Error),
    MissingVariables(Vec<String>),
    InvalidVariable(String),
    CommandFailed { cmd: String, status: ExitStatus },
    KissReplace(#[from] kissreplace::KissReplaceError),
}
```

### `manifest.rs` – The template’s configuration

Deserialises `Inherit.toml` with three optional sections:

```toml
[template]
name = "cargo-lib"
description = "Minimal Rust library template"

[variables]
PROJECT_NAME = "Name of the project"
AUTHOR = "Author name and email"

[hooks]
post_create = ["cargo fmt", "echo 'Done!'"]
```

The `variables` map serves two purposes:

- It **defines** which variables the template expects
(extra variables found in files are also required).
- The string value is a **description** (shown to the user when prompting).

> `#[serde(default)]` makes every field optional – a template can have no manifest at
> all (though you’d lose descriptions and hooks).

### `ignore.rs` – What to skip

`inherit-core` respects two layers of ignoring:

1. **Always ignored** – `"Inherit.toml"`, `".inherignore"`, `".git"` (and anything inside `.git/`).
2. **User‑defined** – via a `.inherignore` file in the template root, using `.gitignore` syntax.

```rust
let ignore = InheritIgnore::load(template_dir);
if ignore.is_ignored(relative_path, is_dir) {
    continue; // skip this file/folder
}
```

You can exclude build artifacts, lock files, or any generated content that shouldn’t be copied into new projects.

### `scanner.rs` – Discovering variables

The scanner walks the template directory (respecting ignores) and reads every text file.
It uses `kissreplace::scan::extract_vars` to find all `@...@` placeholders.
The result is a `HashSet<String>` of **required variable names**.

Why scan? Because a template author might forget to list a variable in `[variables]`.
The scanner ensures nothing is missed – the union of manifest‑declared and scanned
variables becomes the final required set.

### `pipeline.rs` – The heart of the operation

Two public functions drive everything:

#### `load_template(source_dir: &Path) -> Result<TemplateContext>`

Returns a `TemplateContext` containing:

- The parsed `Manifest`
- `required_vars` – all variables that must eventually be provided
- `var_descriptions` – descriptions from the manifest (empty string if not declared)

You’d call this first to show the user a list of what they need to fill in.

#### `process_template(source_dir, target_dir, final_vars, opts) -> Result<ProcessResult>`

This is the real workhorse. It:

- **Validates** variable names (must be `^[A-Z][A-Z0-9_]*$` – by `kissreplace`’s rules).
- **Checks** that all required variables are present and **non‑empty**.
- **Creates** the target directory.
- **Walks** the source, respecting always‑ignored and `.inherignore` entries.
- For each file:
  - If it’s a directory → create it in the target (after replacing placeholders in its name).
  - If it’s a file:
    - Try to read as UTF‑8 → replace placeholders in the **content**, write as text.
    - On failure (binary file) → copy byte‑for‑byte (no replacement).
- If `opts.init_git` is true → runs `git init -q` in the target.
- If `opts.run_hooks` is true → executes each `post_create` command in order.

The function returns counts of processed text files and copied binary files.

## Putting It All Together – A Complete Example

Let’s simulate what the CLI would do. We’ll use the built‑in `cargo-lib` example template.

```rust
use inherit_core::{load_template, process_template, ProcessOptions, Variables};
use std::fs;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let template_dir = "./examples/cargo-lib";
    let target_dir = "./my-new-lib";

    // 1. Load template to know what variables are needed
    let ctx = load_template(template_dir.as_ref())?;
    println!("Required variables: {:?}", ctx.required_vars);

    // 2. Collect values (normally you'd ask the user)
    let mut vars = Variables::new();
    vars.insert("PROJECT_NAME".into(), "my_awesome_lib".into());
    vars.insert("AUTHOR".into(), "Jane Doe <jane@example.com>".into());
    vars.insert("VERSION".into(), "0.1.0".into());
    vars.insert("DESCRIPTION".into(), "Does something cool".into());

    // 3. Process the template
    let opts = ProcessOptions::default(); // init_git = true, run_hooks = true
    let result = process_template(
        template_dir.as_ref(),
        target_dir.as_ref(),
        &vars,
        opts,
    )?;

    println!("Generated {} text files, {} binary files", 
             result.processed_files, result.binary_files);

    // Check that placeholders are gone
    let cargo_toml = fs::read_to_string(target_dir.join("Cargo.toml"))?;
    assert!(!cargo_toml.contains('@'));

    Ok(())
}
```

When you run this, the target directory will contain a fresh Rust library
project with `name = "my_awesome_lib"` and a `.git` folder
(because `init_git` defaulted to `true`).

## Advanced Features

### Placeholders in File and Folder Names

The replacement isn’t limited to file contents – it also applies to **paths**.
This template file:

```
src/@PROJECT_NAME@/mod.rs
```

will be created as `src/my_awesome_lib/mod.rs`. Very useful for language‑specific
layouts (e.g. Python packages, Java namespaces).

### Binary Files are Copied Unchanged

If a file cannot be read as UTF‑8, `inherit-core` assumes it’s binary and performs
a byte‑wise copy. No placeholder replacement happens, so your images or
compiled assets stay intact.

### Post‑Create Hooks on Windows and Unix

The `hooks.post_create` commands are executed using:

- `sh -c "command"` on Unix
- `cmd /C "command"` on Windows

This gives you maximum portability. A typical hook might run `cargo fmt`, `git add .`, or `npm install`.

## Error Handling in Practice

The CLI tool uses `InheritError` to produce user‑friendly messages. For example:

- **MissingVariables** – prints the list of variables the user forgot to provide.
- **CommandFailed** – shows which hook failed and its exit status.
- **ManifestNotFound** – suggests maybe the path isn’t a valid template directory.

Because every error implements `std::error::Error`, you can use `anyhow` or `thiserror` in your own wrapper.

## Testing Strategy

The crate includes integration tests that:

- Run the `cargo-lib` example template end‑to‑end.
- Verify missing variables trigger the right error.
- Test variable replacement inside file names (the `test_variable_in_filename` case).

These tests use `tempfile::tempdir()` to avoid polluting the source tree. They also disable
`init_git` and hooks to keep tests fast and deterministic.

## Why `kissreplace`?

The placeholder engine was deliberately kept tiny and fast. [`kissreplace`] provides:

- **Scanning** – extract all `@VAR@` names from a string.
- **Replacement** – efficient, single‑pass substitution.

Its “kiss” philosophy aligns perfectly with `inherit-core`: no regex magic, no accidental
partial replacements, just clear semantics.

## When to Use `inherit-core` Directly

You might bypass the `cargo-inherit` CLI if you want to:

- Integrate templating into a larger build system (e.g. a workspace generator).
- Provide a different user interface – a TUI, a web form, or environment‑variable driven generation.
- Automate template instantiation in CI/CD pipelines.

Simply add `inherit-core` as a dependency, and you get the entire templating engine without any interactive baggage.

```shell
cargo add inherit-core
```

## Conclusion

`inherit-core` is a focused, well‑tested library that turns any directory into a **reusable, parameterised template**.
It respects ignore files, replaces placeholders everywhere (even in paths), and runs hooks to finalise the generated
project. Whether you’re building the official `cargo-inherit` tool or your own bespoke generator, this crate gives
you a solid foundation – and keeps the magic behind `@YOUR_VARIABLES@`.

Now go ahead, create some templates, and let `inherit-core` do the repetitive work for you!

## Links

[crates.io](https://crates.io/inherit-core)
[docs.rs](https://docs.rs/inherit-core)
