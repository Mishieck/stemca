set shell := ["bash", "-c"]

test suite:
    zig build test-{{suite}}

list:
    zig build run -- list

lookup:
    zig build run -- lookup ai
    @echo ""
    zig build run -- lookup wrong

verify:
    zig build run -- verify

build-all:
     just build aarch64-linux-musl
     just build x86_64-linux-musl
     # just build aarch64-macos
     # just build x86_64-macos
     just build aarch64-windows
     just build x86_64-windows

build target:
    zig build -Doptimize=ReleaseSafe -Dtarget={{target}} --prefix zig-out/{{target}}
    if [[ "{{target}}" == *-windows* ]]; then \
        7z a -tzip zig-out/{{target}}.zip zig-out/{{target}}; \
    else \
        tar -czf zig-out/{{target}}.tar.gz zig-out/{{target}}; \
    fi 
