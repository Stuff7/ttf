const std = @import("std");
const gm = @import("zml");
const zut = @import("zut");
const ttf = @import("ttf");
const zap = @import("zap");
const cli = @import("cli.zig");

const dbg = zut.dbg;
const utf8 = zut.utf8;

pub fn main() !void {
    var arena = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        // zig fmt: off
        dbg.usage(args[0], .{
            "info ", "Print info about a glyph",
            "glyph", "Store a single glyph in a file",
            "atlas", "Store a group of glyphs in a file",
        });
        // zig fmt: on
        return;
    }

    if (std.mem.eql(u8, args[1], "atlas")) {
        try cli.atlas(allocator, args[1..]);
    } else if (std.mem.eql(u8, args[1], "glyph")) {
        try cli.glyph(allocator, args[1..]);
    } else if (std.mem.eql(u8, args[1], "info")) {
        try cli.info(allocator, args[1..]);
    } else {
        dbg.print("Unrecognized option", .{});
    }
}
