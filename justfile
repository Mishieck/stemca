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
