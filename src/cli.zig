const std = @import("std");
const ttf = @import("ttf");
const zut = @import("zut");
const gm = @import("zml");

const utf8 = zut.utf8;
const dbg = zut.dbg;
const Allocator = std.mem.Allocator;

pub fn info(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        const options = comptime utf8.clr("190") ++ "<ttf> <glyph>" ++ utf8.esc("0");
        var exe: [options.len + 50]u8 = undefined;
        // zig fmt: off
        dbg.usage(try std.fmt.bufPrint(&exe, "{s} {s}", .{args[0], options}), .{
            "ttf  ", "Path to ttf file",
            "glyph", "Show info about this glyph",
        });
        // zig fmt: on
        return;
    }

    var parser = try ttf.GlyphParser.parse(allocator, args[1]);
    defer parser.deinit();
    const c = try std.unicode.utf8Decode(args[2]);
    const g = try parser.getGlyph(allocator, c);

    if (g == .compound) {
        dbg.dump(g.compound);
    }

    const simple = try g.simplify(&parser);
    defer simple.deinit();
    dbg.dump(simple);
}

pub fn atlas(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 6) {
        const options = comptime utf8.clr("190") ++ "<ttf> <atlas> <width> <height> <glyphs> <scale?>" ++ utf8.esc("0");
        var exe: [options.len + 50]u8 = undefined;
        // zig fmt: off
        dbg.usage(try std.fmt.bufPrint(&exe, "{s} {s}", .{args[0], options}), .{
            "ttf   ", "Path to ttf file",
            "atlas ", "Output path for atlas file",
            "width ", "Glyph width",
            "height", "Glyph height",
            "glyphs", "String of glyphs",
            "scale ", "Glyph scale",
        });
        // zig fmt: on
        return;
    }

    var parser = try ttf.GlyphParser.parse(allocator, args[1]);
    defer parser.deinit();
    const w = try std.fmt.parseUnsigned(u32, args[3], 10);
    const h = try std.fmt.parseUnsigned(u32, args[4], 10);
    const s = if (args.len > 6) std.fmt.parseFloat(f32, args[6]) catch 1 else 1;
    try ttf.Atlas.write(allocator, args[2], &parser, w, h, args[5], s);
    const a = try ttf.Atlas.read(allocator, args[2]);
    defer a.deinit();
    dbg.dump(a);
}

pub fn glyph(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 7) {
        const options = comptime utf8.clr("190") ++ "<ttf> <glyph> <width> <height> <format> <scale?>" ++ utf8.esc("0");
        var exe: [options.len + 50]u8 = undefined;
        // zig fmt: off
        dbg.usage(try std.fmt.bufPrint(&exe, "{s} {s}", .{args[0], options}), .{
            "ttf   ", "Path to ttf file",
            "output", "Output path for glyph file",
            "glyph ", "Glyph to extract",
            "width ", "Glyph width",
            "height", "Glyph height",
            "format", "Glyph file format bmp/bmp-contour/fl32",
            "scale ", "Glyph scale (default 0.8)",
        });
        // zig fmt: on
        return;
    }

    var parser = try ttf.GlyphParser.parse(allocator, args[1]);
    defer parser.deinit();
    const w = try std.fmt.parseUnsigned(u32, args[4], 10);
    const h = try std.fmt.parseUnsigned(u32, args[5], 10);
    const s = if (args.len > 7) std.fmt.parseFloat(f32, args[7]) catch 1 else 1;
    const c = try std.unicode.utf8Decode(args[3]);

    if (std.mem.eql(u8, args[6][0..3], "bmp")) {
        const g = try parser.getGlyph(allocator, c);
        var simple = try g.simplify(&parser);
        defer simple.deinit();

        simple.normalizeEm(parser.head.units_per_em);
        try simple.addImplicitPoints(allocator);
        simple.scale(s);
        dbg.dump(simple.glyf);

        if (std.mem.eql(u8, args[6][3..], "-contour")) {
            try ttf.drawGlyphContourBmp(allocator, simple, @intCast(w), @intCast(h), args[2]);
        } else {
            try ttf.drawGlyphBmp(allocator, simple, @intCast(w), @intCast(h), args[2]);
        }
    } else if (std.mem.eql(u8, args[6], "fl32")) {
        const g = try parser.getGlyph(allocator, c);
        var simple = try g.simplify(&parser);
        defer simple.deinit();

        simple.normalizeEm(parser.head.units_per_em);
        try simple.addImplicitPoints(allocator);
        simple.scale(s);

        try ttf.drawGlyphFl32(allocator, simple, w, h, args[2]);
    }
}
