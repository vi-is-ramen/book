# Faces – Unifying Interfaces Across Crates

In any sufficiently complex Rust project, you eventually run into the same problem:
two crates (or components) that should work together speak slightly different
languages. One expects a `Vec<u8>`, the other provides a `&[u8]`. One uses a
custom `Mutex` type, the other uses `std::sync::Mutex`. You end up writing glue
code – and lots of it.

**Faces** is a minimal, no‑std compatible crate that gives you a set of primitive
types and abstract traits designed to be **extended infinitely**. Instead of
forcing a particular implementation, Faces provides the *faces* – the common
interfaces – that you can implement for your own types. This way, two otherwise
incompatible APIs can talk to each other through a shared abstraction.

## The Philosophy

Faces is not a framework. It doesn't dictate how you manage memory, handle
concurrency, or convert values. What it does is:

- Define **core traits** like `Convertable<T>`, `AbsMutex<T>`,
`AbsPageFrameManager`, etc.
- Provide **trivial types** like `PageFrameNumber`, `PhysicalAddress`,
`VirtualAddress` that are useful in low‑level (e.g., kernel) code.
- Re‑export popular traits (e.g., `serde::{Serialize, Deserialize}`) under
feature flags for convenience.

The key is that you, the crate author, can implement these traits for your own
types. Then any other crate that depends on Faces can use your types through
the same well‑known interface – without pulling in your entire dependency tree.

## Core Traits

### Conversion Traits

The most basic need is converting one type into another. Faces provides
three pairs of safe and unsafe conversion traits:

```rust
pub trait Convertable<T> {
    fn to(self) -> T;
}

pub trait ConvertableRef<T> {
    fn to(&self) -> T;
}

pub trait ConvertableMut<T> {
    fn to(&mut self) -> T;
}
```

And their unsafe counterparts: `UnsafeConvertable`, `UnsafeConvertableRef`,
`UnsafeConvertableMut`. Unsafe conversions are useful when you need to
reinterpret memory (e.g., turning a `VirtualAddress` into a reference).

Example: implementing a safe conversion from `MyId` to `u64`:

```rust
use faces::Convertable;

struct MyId(u32);

impl Convertable<u64> for MyId {
    fn to(self) -> u64 {
        self.0 as u64
    }
}

let id = MyId(42);
let val: u64 = faces::to(id); // or id.to()
```

Helper functions `to`, `ref_to`, `mut_to` are provided for ergonomics.

### Synchronisation Primitives

Faces defines **abstract** locks and synchronisation helpers. These are
not implementations – they are contracts that any concrete lock can implement.

```rust
pub trait AbsMutex<T: ?Sized + Send, R: AbsRelaxStrategy> {
    type Guard<'a>: DerefMut<Target = T> + Send;
    fn lock(&self) -> Result<Self::Guard<'_>, LockError>;
    fn try_lock(&self) -> Result<Self::Guard<'_>, LockError>;
}
```

You can implement `AbsMutex` for `std::sync::Mutex`, `spin::Mutex`, your
own kernel spinlock, etc. The `R: AbsRelaxStrategy` parameter allows you to
specify what “relax” means (e.g., `core::hint::spin_loop` or a yield call).
The same pattern exists for `AbsRwLock`, `AbsOnce`, and `AbsLazy`.

Optional timeout extensions (`AbsMutexTimeout`, `AbsRwLockTimeout`) give
you timed lock attempts.

### Memory Management Primitives

If you work with physical memory (e.g., in an OS kernel or a hypervisor),
you often need abstractions for page frames and addresses.

- `PageFrameNumber`: a simple wrapper around `usize` with arithmetic, bitwise, and
formatting traits. It converts to/from `PhysicalAddress` (assuming 4 KiB pages).
- `PhysicalAddress` and `VirtualAddress`: newtype wrappers for addresses, with
`Display` (hex formatting) and optional `serde` support.
- `AbsPageFrameManager`: a trait that any physical memory manager can implement.
It provides methods to set/clear/check flags on a page frame, query the valid
range, and test presence.
- `AbsAddressTranslator`: converts between virtual and physical addresses.

These are especially useful when writing platform‑agnostic memory management code.
For example, you can write a generic page allocator that works with any
`AbsPageFrameManager`.

## Feature Flags

Faces keeps its dependencies optional:

- **`std`** (enabled by default): enables the standard library. Disable it for
`no_std` environments.
- **`serde`**: derives `Serialize` and `Deserialize` for `PageFrameNumber`,
`PhysicalAddress`, `VirtualAddress` and other future types.
- **`log`**: re‑exports the `log::Log` trait.

In your `Cargo.toml`:

```toml
faces = { version = "0.1", default-features = false, features = ["serde"] }
```

## Extending Faces

Because Faces only provides traits, you are expected to
**implement them for your own types**. That is the “infinite extension” design:
the crate itself will never grow to include every possible conversion or lock type.
Instead, you – and the community – write implementations in your own crates.

For example, if you have a custom `Mutex` type, add this to your crate:

```rust
use faces::{AbsMutex, AbsRelaxStrategy, LockError};
use core::ops::DerefMut;

struct MyMutex<T> { ... }

impl<T: Send, R: AbsRelaxStrategy> AbsMutex<T, R> for MyMutex<T> {
    type Guard<'a> = MyMutexGuard<'a, T>;
    fn lock(&self) -> Result<Self::Guard<'_>, LockError> { ... }
    fn try_lock(&self) -> Result<Self::Guard<'_>, LockError> { ... }
}
```

Now any code that depends on Faces can use `MyMutex` wherever an `AbsMutex` is
required. The same applies to conversions: implement `Convertable<YourType>`
for `TheirType` and vice versa.

## Real‑World Example: Bridging Two Crates

Suppose you have crate A that produces `CustomFrameId` (a page frame number)
and crate B that expects `faces::PageFrameNumber`. Instead of modifying either
crate, you write a small shim:

```rust
use faces::{Convertable, PageFrameNumber};

impl Convertable<PageFrameNumber> for CustomFrameId {
    fn to(self) -> PageFrameNumber {
        PageFrameNumber::new(self.raw())
    }
}

impl Convertable<CustomFrameId> for PageFrameNumber {
    fn to(self) -> CustomFrameId {
        CustomFrameId::from_raw(self.to())
    }
}
```

Now `faces::to::<PageFrameNumber>(custom_id)` works, and the two crates can
communicate without ever knowing about each other’s internal types.

## Where to Go From Here

Faces is intentionally small – its true power comes from the ecosystem of
implementations that others will write. Check out the
[API documentation](https://docs.rs/faces/) for the full list of traits and types.

If you have a useful abstraction that belongs in Faces (e.g., a trait for
asynchronous locks or for reference‑counted pointers), feel free to open an issue
or pull request on [GitHub](https://github.com/vi-is-ramen/faces). The goal is to
keep the set of traits minimal, widely useful, and easy to implement.

**Start using Faces today** – add it to your `Cargo.toml` and begin implementing
those faces. Your future self (and your users) will thank you for the clean,
decoupled interfaces.
