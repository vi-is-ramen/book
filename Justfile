default:
    @just --list | grep -v default

build:
    @rm -rf book
    @cd en; mdbook build
    @cd ru; mdbook build
    @cp index.html book

b: build

_b:
    @[ -f book/index.html ] || just b

run: _b
    @xdg-open book/index.html

r: run

clean:
    @rm -rf book/

c: clean
