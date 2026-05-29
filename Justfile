default:
    @just --list | grep -v default

build:
    @rm -rf book; \
     mkdir book; \
     \
     cd en; \
     mdbook build; \
     cd ..; \
     \
     cd ru; \
     mdbook build; \
     cd ..; \
     \
     cp index.html book/; \
     \
     mkdir -p book/en; \
     cp -r en/book/* book/en; \
     \
     mkdir -p book/ru; \
     cp -r ru/book/* book/ru

b: build

_b:
    @[ -f book/index.html ] || just b

run: _b
    @xdg-open book/index.html

r: run

clean:
    @rm -rf book/

c: clean
