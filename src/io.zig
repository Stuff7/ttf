const std = @import("std");
const zap = @import("zap");
const zut = @import("zut");
const gm = @import("zml");
const ttf = @import("ttf.zig");

const m = std.math;
const dbg = zut.dbg;
const mem = zut.mem;
const SimpleGlyph = ttf.SimpleGlyph;
const Allocator = std.mem.Allocator;

pub fn drawGlyphFl32(allocator: Allocator, glyph: SimpleGlyph, width: u32, height: u32, filename: []const u8) !void {
    var dists = try SdfIterator.init(allocator, glyph, @floatFromInt(width), @floatFromInt(height));
    defer dists.deinit();
    dbg.dump(dists);

    var buffer = try allocator.alloc(f32, width * height);
    defer allocator.free(buffer);

    var i: usize = 0;

    while (dists.next()) |min_dist| : (i += 1) {
        buffer[i] = min_dist;
    }

    const fl32 = zap.Fl32{
        .width = width,
        .height = height,
        .data = buffer,
    };

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    try fl32.write(file.writer());
}

pub fn drawGlyphBmp(allocator: Allocator, glyph: SimpleGlyph, w: usize, h: usize, path: []const u8) !void {
    const buffer = try allocator.alloc(u8, mem.intCast(usize, w * h) * zap.Bmp(24).bytes_per_px);
    defer allocator.free(buffer);
    @memset(buffer, 20);
    var bmp = try zap.Bmp(24).init(w, h, buffer);

    var dists = try SdfIterator.init(allocator, glyph, @floatFromInt(w), @floatFromInt(h));
    defer dists.deinit();
    dbg.dump(dists);

    var i: usize = 0;

    while (dists.next()) |min_dist| : (i += 1) {
        if (@abs(min_dist) <= 0.005) {
            bmp.pixels[i].r = 255;
            bmp.pixels[i].g = 255;
        } else if (min_dist > 0) {
            bmp.pixels[i].g = 128;
            bmp.pixels[i].b = 128;
        }
    }

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try bmp.write(file.writer(), null, null);
}

pub fn drawGlyphContourBmp(allocator: Allocator, glyph: SimpleGlyph, w: usize, h: usize, path: []const u8) !void {
    const buffer = try allocator.alloc(u8, mem.intCast(usize, w * h) * zap.Bmp(24).bytes_per_px);
    defer allocator.free(buffer);
    @memset(buffer, 20);
    var bmp = try zap.Bmp(24).init(w, h, buffer);

    const shape = try glyph.shape(allocator);
    defer SimpleGlyph.deinitShape(allocator, shape);
    dbg.dump(shape);

    for (shape.segments) |segment| {
        switch (segment) {
            .line => |s| drawLineBmp(bmp, s.p0, s.p1, 255),
            .curve => |s| drawQuadBezierBmp(bmp, s.p0, s.p1, s.p2, 255),
        }
    }

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try bmp.write(file.writer(), null, null);
}

pub fn drawLineBmp(bmp: zap.Bmp(24), p0: gm.Vec2, p1: gm.Vec2, color: u8) void {
    const v = gm.Vec2{ mem.asFloat(f32, bmp.width), mem.asFloat(f32, bmp.height) };
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
        if (x0 >= 0 and x0 < bmp.width and y0 >= 0 and y0 < bmp.height) {
            const i: usize = @intCast(y0 * mem.intCast(isize, bmp.width) + x0);
            bmp.pixels[i].g = color;
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

pub fn drawQuadBezierBmp(bmp: zap.Bmp(24), p0: gm.Vec2, p1: gm.Vec2, p2: gm.Vec2, color: u8) void {
    const steps: f32 = 64;
    var i: f32 = 0;
    while (i < steps) : (i += 1) {
        const t0 = i / steps;
        const t1 = (i + 1) / steps;

        const q0 = gm.vec2.lerp(gm.vec2.lerp(p0, p1, t0), gm.vec2.lerp(p1, p2, t0), t0);
        const q1 = gm.vec2.lerp(gm.vec2.lerp(p0, p1, t1), gm.vec2.lerp(p1, p2, t1), t1);

        drawLineBmp(bmp, q0, q1, color);
    }
}

pub const SdfIterator = struct {
    allocator: Allocator,
    sdf: gm.Sdf = gm.Sdf{},
    shape: gm.Shape,
    viewport: gm.Vec2,
    position: gm.Vec2 = gm.Vec2{ 0, 0 },
    curr_pos: gm.Uvec2 = gm.Uvec2{ 0, 0 },

    pub fn init(allocator: Allocator, glyph: SimpleGlyph, width: f32, height: f32) !SdfIterator {
        return SdfIterator{
            .allocator = allocator,
            .shape = try glyph.shape(allocator),
            .viewport = gm.Vec2{ width, height },
        };
    }

    pub fn deinit(self: SdfIterator) void {
        SimpleGlyph.deinitShape(self.allocator, self.shape);
    }

    pub fn next(self: *SdfIterator) ?f32 {
        if (self.position[1] == self.viewport[1]) {
            return null;
        }

        const p = self.position / self.viewport;
        var min_dist = m.floatMax(f32);

        const dist = try self.sdf.shapeDistance(self.shape, p);
        if (@abs(dist) < @abs(min_dist)) {
            min_dist = dist;
        }

        self.curr_pos = @intFromFloat(self.position);

        if (self.position[1] < self.viewport[1] and self.position[0] == self.viewport[0] - 1) {
            self.position[1] += 1;
            self.position[0] = 0;
        } else {
            self.position[0] += 1;
        }

        return min_dist;
    }
};
