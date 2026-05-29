# `wrapcli`: Fake Command Identity With Ease

**wrapcli** is a Rust library that wraps an existing CLI tool and rewrites its output on the fly, making it appear as if a different tool produced the output.

### Features

- Stream real-time output rewriting (line by line)
- Capture full output for post-processing
- Customizable rewriting rules
- Preserve original version information (optional)

### Use Cases

- Create branded variants of CLI tools
- Mask internal tool names in user-facing output
- Add version information without changing the underlying tool
- Integrate legacy tools into modern workflows

## Getting Started

### Installation

Add `wrapcli` to your dependencies:

```shell
cargo add wrapcli
```

### Basic Usage

```rust
use wrapcli::{run_streaming, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "rustc".into(),
        fake_name: "dustc".into(),
        fake_ver: "2.0.0".into(),
        save_orig: true,
    };

    let args: Vec<String> = std::env::args().skip(1).collect();
    let status = run_streaming(&cfg, args)?;
    std::process::exit(status.code().unwrap_or(1));
}
```

## How It Works

When the wrapped tool outputs a line containing the original name, `wrapcli` intercepts it and applies rewriting rules:

1. The **first occurrence** of the original tool's name and version is replaced with the fake name and fake version. If `save_orig` is `true`, the original version is appended in parentheses.
2. Any **subsequent occurrences** of the original name in usage lines are replaced with the fake name.

This ensures consistent output masking without breaking the tool's functionality.

## Configuration

The `WrapConfig` struct controls the rewriting behavior.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `orig_name` | `String` | The original tool's name (e.g., `"rustc"`) |
| `fake_name` | `String` | The name to display instead (e.g., `"dustc"`) |
| `fake_ver` | `String` | The version string to display (e.g., `"2.0.0"`) |
| `save_orig` | `bool` | Whether to append the original version in parentheses |

### Example

```rust
use wrapcli::WrapConfig;

let cfg = WrapConfig {
    orig_name: "git".into(),
    fake_name: "gitter".into(),
    fake_ver: "3.0.0".into(),
    save_orig: false,
};
```

## Examples

### Streaming Output

```rust
use wrapcli::{run_streaming, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "cargo".into(),
        fake_name: "pargo".into(),
        fake_ver: "2.0.0".into(),
        save_orig: true,
    };

    let args = vec!["--version".to_string()];
    run_streaming(&cfg, args)?;
    Ok(())
}
```

### Capturing Output

```rust
use wrapcli::{run_capture, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "rustc".into(),
        fake_name: "dustc".into(),
        fake_ver: "2.0.0".into(),
        save_orig: false,
    };

    let args = vec!["--version".to_string()];
    let result = run_capture(&cfg, args)?;
    
    println!("Captured stdout: {}", String::from_utf8_lossy(&result.stdout));
    println!("Captured stderr: {}", String::from_utf8_lossy(&result.stderr));
    Ok(())
}
```

### Real-World Example: Wrapping Git

```rust
use wrapcli::{run_streaming, WrapConfig};
use std::env;

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "git".into(),
        fake_name: "gitter".into(),
        fake_ver: "3.0.0".into(),
        save_orig: true,
    };

    let args: Vec<String> = env::args().skip(1).collect();
    run_streaming(&cfg, args)
}
```

## Links

[crates.io](https://crates.io/wrapcli)
[docs.rs](https://docs.rs/wrapcli)
