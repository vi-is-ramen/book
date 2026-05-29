# `cargo-inherit` – The Inherit CLI

Welcome to `cargo-inherit` – the command‑line tool that turns any Git repository into a
reusable, customisable project template. If you’ve ever copied a boilerplate project and
then manually replaced all the placeholders, this tool is for you.

`cargo-inherit` is a thin but powerful wrapper around [`inherit-core`](./inherit-core.md).
It adds:

- **Template discovery** – from GitHub or any Git URL
- **Aliases** – short names for long template paths
- **Default values** – pre‑fill variables like `AUTHOR`
- **Smart caching** – cloned templates are stored for speed
- **Interactive prompts** – ask for missing variables with nice defaults
- **Post‑creation hooks** – run shell commands after generation
(e.g. `cargo fmt`, `git add .`)
- **Configuration file** – keep your preferences and secrets safe

Let’s dive in!

## Installation

`cargo-inherit` is a Rust binary. Install it from crates.io:

```bash
cargo install cargo-inherit
```

Make sure `~/.cargo/bin` is in your `PATH`. After installation, the command is `cargo-inherit` – but you can also use `inherit` if you add an alias or rename the binary.

> **Note:** The binary is named `cargo-inherit`, but the examples in this chapter will use `inherit` for brevity. In practice you can run `cargo inherit` if you have `cargo-inherit` installed (Cargo forwards subcommands).

## Quick Start

Generate a new Rust library from the hypothetical `cargo-lib` template:

```bash
inherit rust-lib/cargo-lib to my-project
```

The CLI will:

1. Clone `https://github.com/rust-lib/cargo-lib` (cached for next time).
2. Read `Inherit.toml` and scan all files for `@VARIABLES@`.
3. Ask you for values (with helpful descriptions and defaults from config).
4. Generate `my-project/` with all placeholders replaced.
5. Run `git init` and execute any `post_create` hooks.

If you have a local template directory, you can use a `file://` URL or an absolute path:

```bash
inherit /home/me/my-templates/rust-lib
```

## Commands Reference

### `generate` – The Main Event

**Syntax:** `inherit <template> [to <directory>]`

- `template` – can be:
  - `user/repo` (GitHub shorthand)
  - full URL (`https://...`, `file://...`, or absolute path)
  - an alias (see below)
- `directory` – where to create the project (defaults to current directory)

**Example:**

```bash
inherit alice/awesome-template to my-app
```

If `alice/awesome-template` requires variables like `PROJECT_NAME` and `AUTHOR`, you’ll be prompted interactively. Values from your config’s `[defaults]` table are offered as suggestions.

### `alias` – Shorten Your Favourite Templates

| Command | Description |
|---------|-------------|
| `inherit <template> to alias <name>` | Create an alias for a template |
| `inherit alias list` | Show all aliases |
| `inherit alias remove <name>` | Delete an alias |

**Example:**

```bash
# Add alias
inherit rust-lib/cargo-lib to alias rlib

# Use it later
inherit rlib to new-project

# See all aliases
inherit alias list

# Remove it
inherit alias remove rlib
```

Aliases are stored in your config file under `[aliases]`.

### `default` – Pre‑set Variable Values

| Command | Description |
|---------|-------------|
| `inherit default for <VAR>` | Set a default value for a variable |
| `inherit default list` | Show all defaults |
| `inherit default unset <VAR>` | Remove a default |

Defaults are used as the **initial suggestion** when the prompt appears. You can still override them by typing a different value.

**Example:**

```bash
# Set your name once
inherit default for AUTHOR
# > prompts: "Default value for AUTHOR [Your Name <you@example.com>]:"
# Type a new value or press Enter to keep the current one.

# Later, every template that asks for AUTHOR will suggest this value.
```

Defaults are stored in `[defaults]` in the config file.

### `cache` – Manage Downloaded Templates

| Command | Description |
|---------|-------------|
| `inherit cache list` | Show cached templates and their disk usage |
| `inherit cache clean` | Delete everything in the cache |

Templates are cached after the first clone. This speeds up subsequent generations and allows offline use. The cache directory is configurable (see below).

## Configuration File

On first run, `cargo-inherit` creates a config file at:

- **Linux / macOS:** `~/.config/inherit/config.toml`
- **Windows:** `%APPDATA%\inherit\config.toml`

You can override the location with the `INHERIT_CONFIG` environment variable.

Here’s a full annotated example:

```toml
# Default values for template variables.
# When a template requires a variable listed here, its value is used as the
# default suggestion — you can still override it via the interactive prompt.
[defaults]
AUTHOR = "Your Name <you@example.com>"
VERSION = "0.1.0"

# Short aliases for templates.
[aliases]
rlib = "rust-lib/cargo-lib"
blog = "https://github.com/my/blog-template.git"

# Directory used to cache downloaded templates.
# Supports ~/ expansion.
cache_dir = "~/.cache/inherit"

# GitHub personal access token (for private repositories).
# Must have "repo" scope.
github_token = "ghp_..."

# Whether to automatically run `git init` in generated projects.
init_git = true

# Whether to execute `post_create` hooks defined by templates.
run_hooks = true

# Command to open the project after generation (e.g., "code", "nvim", "idea").
open_with = "code"
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `INHERIT_CONFIG` | Full path to config file (overrides default) |
| `INHERIT_CACHE_DIR` | Directory for cached templates (overrides `cache_dir`) |
| `INHERIT_NON_INTERACTIVE` | If set to `1`, never prompt – fails if defaults missing |

Non‑interactive mode is useful in CI or scripts. Example:

```bash
INHERIT_NON_INTERACTIVE=1 inherit user/repo to output
```

## How It Works Under the Hood

When you run `inherit user/repo`:

1. **Resolve** – `user/repo` is transformed into a Git URL (`https://github.com/user/repo.git`) unless it’s an alias or a full URL.
2. **Fetch** – `git clone --depth 1` is used to download the template into the cache (keyed by the canonical URL). Subsequent runs reuse the cached copy.
3. **Load** – `inherit-core` reads `Inherit.toml` and scans all files for `@VAR@` placeholders, respecting `.inherignore`.
4. **Prompt** – For every variable found, the CLI shows a prompt with its description (from `[variables]`) and your configured default (from `[defaults]`).
5. **Process** – All files and folders are copied to the target directory, with `@VAR@` replaced in **both contents and filenames**. Binary files are copied unchanged.
6. **Finalise** – If `init_git = true`, a fresh `git init` is run in the target. Then any `post_create` hooks from the template are executed (using `sh -c` on Unix, `cmd /C` on Windows).
7. **Open** – If `open_with` is set, the CLI launches that command with the target directory as an argument.

### Template Manifest (`Inherit.toml`)

Example for hypothetical `cargo-lib` template:

```toml
[template]
name = "cargo-lib"
description = "Minimal Rust library template"

[variables]
PROJECT_NAME = "Name of the project"
AUTHOR = "Author name and email"
VERSION = "Initial version"
DESCRIPTION = "Short description of the library"

[hooks]
post_create = ["cargo fmt", "git add ."]
```

- `[variables]` keys are the placeholders (without `@`). Their values are **descriptions** shown to the user.
- `post_create` commands are run in the generated project directory.

### The `.inherignore` File

Just like `.gitignore`, but for excluding files from the **template**. Example:

```
target/
Cargo.lock
.git/
```

Any file or folder matching these patterns will **not** be copied into the new project. This keeps your template clean of build artifacts or tool‑specific clutter.

## Advanced Topics

### Using Private GitHub Repositories

Set `github_token` in your config. The token is inserted into the clone URL:

```
https://<token>@github.com/user/repo.git
```

Make sure your token has at least `repo` scope.

### Local Templates Without Git

You can point directly to a directory:

```bash
inherit /absolute/path/to/template
```

The tool will **not** try to clone it; it will use the directory as‑is. This is perfect for rapid iteration.

### Caching Behaviour

- Each template is cached under a **stable identifier** derived from its canonical URL.
- `git clone --depth 1` is used to keep the cache small.
- To update a cached template, delete it from the cache (`inherit cache clean` will nuke everything) or manually run `git pull` inside the cache directory.

### Post‑Create Hooks Security

Hooks are just shell commands. They run with the same privileges as the user. Use them responsibly – do not clone untrusted templates without reviewing their `Inherit.toml`.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `error: Manifest "..." not found` | The template directory is missing an `Inherit.toml` file. Every valid template must have one (even if empty). |
| `error: The following required variables are missing: [...]` | You ran in non‑interactive mode without providing defaults for those variables. Either set them in `[defaults]` or run without `INHERIT_NON_INTERACTIVE`. |
| `git clone failed` | Check your network, the repository URL, and your GitHub token if private. |
| `cannot determine config directory` | `dirs` crate failed. Set `INHERIT_CONFIG` explicitly. |
| `Invalid variable name` | Variable names must match `[A-Z][A-Z0-9_]*` (uppercase, underscore allowed). |

## Putting It All Together – A Real‑World Workflow

Imagine you maintain a company template for microservices:

1. **Write the template** in a repo `mycorp/microservice-template`.
2. **Add aliases** for your team:

   ```bash
   inherit mycorp/microservice-template to alias mcsrv
   ```

3. **Set company defaults**:

   ```bash
   inherit default for AUTHOR
   # -> type "Engineering Team <eng@mycorp.com>"
   inherit default for LICENSE
   # -> type "MIT OR Apache-2.0"
   ```

4. **Generate a new service**:

   ```bash
   inherit mcsrv to payment-service
   ```

   The tool will ask only for the *project‑specific* variables (e.g. `SERVICE_NAME`, `PORT`). The company defaults are already filled.

5. **Automatically open in VS Code** and run `cargo build` via a hook – your team is productive in seconds.

## Conclusion

`cargo-inherit` brings the power of templating to your terminal, with a focus on simplicity and reusability. Whether you’re scaffolding a personal blog, a microservice, or an entire monorepo, this tool will save you from tedious copy‑paste and search‑replace.

The CLI is the friendly face of the [`inherit-core`](./inherit-core.md) engine. Together they form a lightweight, Git‑native templating system that fits naturally into your development workflow.

Give it a try – your future self will thank you.

## Links

[crates.io](https://crates.io/cargo-inherit)
[docs.rs](https://docs.rs/cargo-inherit)
