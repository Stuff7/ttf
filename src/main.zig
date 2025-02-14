const std = @import("std");
const gm = @import("zml");
const zut = @import("zut");
const ttf = @import("ttf");
const zap = @import("zap");
const io = @import("io.zig");

const dbg = zut.dbg;
const utf8 = zut.utf8;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        // zig fmt: off
        dbg.usage(args[0], .{
            "glyph", "Store a single glyph in a file",
            "atlas", "Store a group of glyphs in a file",
        });
        // zig fmt: on
        return;
    }

    if (std.mem.eql(u8, args[1], "atlas")) {
        if (args.len < 6) {
            const options = comptime utf8.clr("190") ++ "<ttf> <atlas> <width> <height> <glyphs>" ++ utf8.esc("0");
            var exe: [options.len + 50]u8 = undefined;
            // zig fmt: off
            dbg.usage(try std.fmt.bufPrint(&exe, "{s} {s} {s}", .{args[0], args[1], options}), .{
                "ttf   ", "Path to ttf file",
                "atlas ", "Output path for atlas file",
                "width ", "Glyph width",
                "height", "Glyph height",
                "glyphs", "String of glyphs",
            });
            // zig fmt: on
            return;
        }

        var parser = try ttf.GlyphParser.parse(allocator, args[2]);
        dbg.dump(parser);
        const w = try std.fmt.parseUnsigned(u32, args[4], 10);
        const h = try std.fmt.parseUnsigned(u32, args[5], 10);
        try ttf.Atlas.write(allocator, args[3], &parser, w, h, args[6]);
        dbg.dump(try ttf.Atlas.read(allocator, args[3]));
    } else if (std.mem.eql(u8, args[1], "glyph")) {
        if (args.len < 7) {
            const options = comptime utf8.clr("190") ++ "<ttf> <glyph> <width> <height> <format>" ++ utf8.esc("0");
            var exe: [options.len + 50]u8 = undefined;
            // zig fmt: off
            dbg.usage(try std.fmt.bufPrint(&exe, "{s} {s} {s}", .{args[0], args[1], options}), .{
                "ttf   ", "Path to ttf file",
                "output", "Output path for glyph file",
                "glyph ", "Glyph to extract",
                "width ", "Glyph width",
                "height", "Glyph height",
                "format", "Glyph file format bmp/bmp-contour/fl32",
            });
            // zig fmt: on
            return;
        }

        var parser = try ttf.GlyphParser.parse(allocator, args[2]);
        const w = try std.fmt.parseUnsigned(u32, args[5], 10);
        const h = try std.fmt.parseUnsigned(u32, args[6], 10);
        const c = try std.unicode.utf8Decode(args[4]);

        if (std.mem.eql(u8, args[7][0..3], "bmp")) {
            var g = try parser.getGlyph(allocator, c);
            g.simple.normalize();
            try g.simple.addImplicitPoints(allocator);
            g.simple.scale(0.9);
            dbg.dump(g.simple.glyf);
            g.simple.center(gm.Vec2{ 1, 1 });

            if (std.mem.eql(u8, args[7][3..], "-contour")) {
                try io.drawGlyphContourBmp(allocator, g.simple, @intCast(w), @intCast(h), args[3]);
            } else {
                try io.drawGlyphBmp(allocator, g.simple, @intCast(w), @intCast(h), args[3]);
            }
        }
    } else {
        dbg.print("Unrecognized option", .{});
    }
}
