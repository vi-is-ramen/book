# Introduction

Welcome to my digital workshop.

You’ve stumbled upon a living collection of code, ideas, and experiments - part documentation,
part developer’s journal, and entirely a reflection of what keeps me tinkering late into the night.

My name is **Ivan Chetchasov**. I write systems in Rust, design programming languages for fun, and
occasionally argue with compilers about borrow checking. This book is where I gather the fruits of
that labour: libraries, utilities, and whatever else emerges from the intersection of curiosity and
caffeine.

## What You’ll Find Inside

This isn’t a single‑product manual. It’s a **workshop** — each chapter stands on its own, but
together they show a consistent philosophy:

- **Practicality first** – If it doesn’t solve a real problem, it doesn’t belong here.
- **Educational by accident** – I write code that’s readable, and I explain why things work
the way they do.
- **Experimental without apology** – Some projects are production‑ready; others are
playgrounds. Both are valuable.

Here’s a taste of what’s already inside (and what’s coming):

### The `inherit` Ecosystem

A Git‑native templating system that turns any repository into a reusable project generator.  
No more copy‑paste‑search‑replace. Just `cargo inherit user/template to my-project`.

- `inherit-core` – the engine that scans, replaces, and respects `.inherignore`
- `cargo-inherit` – the CLI that adds aliases, defaults, caching, and interactive prompts

[> Read more](./my-crates/cargo-inherit.md)

### A Rust Dialect (Working Title: "Dust")

This is a secret so far ;P

### Utility Crates

- `kissreplace` – stupid‑simple placeholder replacement (scan, replace, validate)
- `lazyget` – lazy loading with caching
- `inherit-core` and `cargo-inherit` (already mentioned)
- And more that will appear as I write them

[> Read more on kissreplace](./my-crates/kissreplace.md)
[> Read more on lazyget](./my-crates/lazyget.md)

### Blog‑Style Posts

From time to time I’ll drop a chapter that isn’t code‑heavy but reflects on:

- “Why I rewrote the template scanner three times”
- “Lessons from building a small GUI library”
- “The joy and pain of custom Rust-like syntax”

Think of it as a technical blog embedded in a book.

## How to Read This Book

The chapters are arranged roughly by maturity:

- **Done ✅** – `inherit-core`, `cargo-inherit` (full-featured guides for existing crates)
- **In Progress ⏳** – you already can read it, but it can contain disinfo or typos
- **Experimental ⚠️** – sort of chapters not for wide audicy
- **Blog ❤️** – random thoughts and post‑mortems

You can jump directly to any chapter. The sidebar navigation is your friend.

## Contact & Contributions

I love hearing from readers — whether it’s a bug report, a question, or just “hey, this helped me”.

- **Email**: [vi.is.chapmann@gmail.com](mailto:vi.is.chapmann@gmail.com)
- **Telegram**: [@viqxq](https://t.me/viqxq)
- **WhatsApp**: [+7(993)3533292](https://wa.me/79933533292)

If you find a typo, a broken link, or a code snippet that doesn’t compile, please let me know.  
Better yet, open a pull request on the [GitHub repository for this book](https://github.com/viraven/book).

## A Note on “Ivan Chetchasov”

Yes, that’s my real name. Yes, it’s a mouthful. You can call me **Ivan** or **Vi** — I answer to both. The `vi.is.chapmann` email address is a tiny homage to my past.

## Ready?

Let’s build something interesting.

> “The best way to predict the future is to implement it.”  
> — Alan Kay (sort of)

Proceed to the next chapter, or pick whatever catches your eye. The code is waiting.
