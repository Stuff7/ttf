const std = @import("std");
const ttf = @import("ttf");
const zap = @import("zap");
const zut = @import("zut");
const gm = @import("zml");

const m = std.math;
const dbg = zut.dbg;
const mem = zut.mem;
const SimpleGlyph = ttf.SimpleGlyph;
const Allocator = std.mem.Allocator;

pub fn drawGlyphBmp(allocator: Allocator, glyph: SimpleGlyph, w: i32, h: i32, path: []const u8) !void {
    var bmp = try zap.Bmp(24).init(.{ .width = w, .height = h }, path);
    const buffer = try allocator.alloc(u8, mem.intCast(usize, w * h) * bmp.px_len);
    @memset(buffer, 20);

    var sdf = gm.Sdf{};
    const shape = try glyph.shape(allocator);
    defer SimpleGlyph.deinitShape(allocator, shape);
    dbg.dump(shape);

    const viewport = gm.Vec2{ mem.asFloat(f32, w), mem.asFloat(f32, h) };
    const pixels = bmp.pixels(buffer);
    for (0..bmp.height) |y| {
        for (0..bmp.width) |x| {
            const p = gm.Vec2{ mem.asFloat(f32, x), mem.asFloat(f32, y) } / viewport;
            var min_dist = m.floatMax(f32);

            const dist = try sdf.shapeDistance(shape, p);
            if (@abs(dist) < @abs(min_dist)) {
                min_dist = dist;
            }

            const i = y * bmp.width + x;
            if (@abs(min_dist) <= 0.005) {
                pixels[i].r = 255;
                pixels[i].g = 255;
            } else if (min_dist > 0) {
                pixels[i].g = 128;
                pixels[i].b = 128;
            }
        }
    }

    try bmp.writeData(buffer);
}

pub fn drawGlyphContourBmp(allocator: Allocator, glyph: SimpleGlyph, w: i32, h: i32, path: []const u8) !void {
    var bmp = try zap.Bmp(24).init(.{ .width = w, .height = h }, path);
    const buffer = try allocator.alloc(u8, mem.intCast(usize, w * h) * bmp.px_len);
    @memset(buffer, 20);

    const shape = try glyph.shape(allocator);
    dbg.dump(shape);

    const pixels = bmp.pixels(buffer);
    for (shape.segments) |segment| {
        switch (segment) {
            .line => |s| drawLineBmp(pixels, w, h, s.p0, s.p1, 255),
            .curve => |s| drawQuadBezierBmp(pixels, w, h, s.p0, s.p1, s.p2, 255),
        }
    }

    try bmp.writeData(buffer);
}

pub fn drawLineBmp(pixels: []zap.Bmp(24).Rgb, width: i32, height: i32, p0: gm.Vec2, p1: gm.Vec2, color: u8) void {
    const v = gm.Vec2{ mem.asFloat(f32, width), mem.asFloat(f32, height) };
    const p0v = p0 * v;
    const p1v = p1 * v;
    var x0: isize = @intFromFloat(p0v[0]);
    var y0: isize = @intFromFloat(p0v[1]);
    const x1: isize = @intFromFloat(p1v[0]);
    const y1: isize = @intFromFloat(p1v[1]);

    const dx: isize = @intCast(@abs(x1 - x0));
    const sx: isize = if (x0 < x1) 1 else -1;
    const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
    const sy: isize = if (y0 < y1) 1 else -1;
    var err: isize = dx + dy;
    var e2: isize = 0;

    while (true) {
        if (x0 >= 0 and x0 < width and y0 >= 0 and y0 < height) {
            const i: usize = @intCast(y0 * mem.intCast(isize, width) + x0);
            pixels[i].g = color;
        }
        if (x0 == x1 and y0 == y1) {
            break;
        }
        e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

pub fn drawQuadBezierBmp(pixels: []zap.Bmp(24).Rgb, width: i32, height: i32, p0: gm.Vec2, p1: gm.Vec2, p2: gm.Vec2, color: u8) void {
    const steps: f32 = 64;
    var i: f32 = 0;
    while (i < steps) : (i += 1) {
        const t0 = i / steps;
        const t1 = (i + 1) / steps;

        const q0 = gm.vec2.lerp(gm.vec2.lerp(p0, p1, t0), gm.vec2.lerp(p1, p2, t0), t0);
        const q1 = gm.vec2.lerp(gm.vec2.lerp(p0, p1, t1), gm.vec2.lerp(p1, p2, t1), t1);

        drawLineBmp(pixels, width, height, q0, q1, color);
    }
}
