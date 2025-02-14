const std = @import("std");
const zut = @import("zut");
const gm = @import("zml");
const ttf = @import("ttf.zig");

const m = std.math;
const dbg = zut.dbg;
const utf8 = zut.utf8;
const Allocator = std.mem.Allocator;
const GlyphParser = ttf.GlyphParser;
const SimpleGlyph = ttf.SimpleGlyph;

pub const Atlas = struct {
    num_glyphs: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    glyph_width: u32 = 0,
    glyph_height: u32 = 0,
    allocator: Allocator,
    glyphs: []u8 = "",
    data: []f32 = &[0]f32{},

    const header_id = "FL32ATLS";

    pub fn read(allocator: Allocator, path: []const u8) !Atlas {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var header = [_]u8{0} ** 8;
        _ = try file.read(&header);
        try dbg.rtAssert(std.mem.eql(u8, &header, header_id), error.NoFL32);

        var self = try zut.mem.packedRead(Atlas, file, "allocator");
        self.allocator = allocator;

        var glyphs_byte_len: u32 = 0;
        _ = try file.read(std.mem.asBytes(&glyphs_byte_len));
        self.glyphs = try allocator.alloc(u8, glyphs_byte_len);
        _ = try file.read(self.glyphs);

        const data = try file.readToEndAllocOptions(allocator, 100e6, null, @alignOf(f32), null);
        self.data = std.mem.bytesAsSlice(f32, data);

        return self;
    }

    pub fn write(allocator: Allocator, filename: []const u8, parser: *GlyphParser, width: u32, height: u32, glyphs: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var w = std.io.bufferedWriter(file.writer());

        _ = try w.write(header_id);

        const num_glyphs: u32 = @intCast(try utf8.charLength(glyphs));
        _ = try w.write(std.mem.asBytes(&num_glyphs));

        const size = @sqrt(@as(f32, @floatFromInt(num_glyphs)));
        const cols: u32 = @intFromFloat(@ceil(size));
        const rows: u32 = @intFromFloat(@round(size));
        const atlas_w: u32 = cols * width;
        const atlas_h: u32 = rows * height;
        _ = try w.write(std.mem.asBytes(&atlas_w));
        _ = try w.write(std.mem.asBytes(&atlas_h));

        _ = try w.write(std.mem.asBytes(&width));
        _ = try w.write(std.mem.asBytes(&height));

        _ = try w.write(std.mem.asBytes(&@as(u32, @intCast(glyphs.len))));
        _ = try w.write(glyphs);

        var buffer = try allocator.alloc(f32, atlas_w * atlas_h);
        defer allocator.free(buffer);
        @memset(buffer, -1);

        var chars = (try std.unicode.Utf8View.init(glyphs)).iterator();
        var i: usize = 0;
        while (chars.nextCodepoint()) |c| : (i += 1) {
            const x = i % cols;
            const y = rows - 1 - i / cols;
            var g = try parser.getGlyph(allocator, c);
            switch (g) {
                .simple => |*simple| {
                    simple.normalizeEm(parser.head.units_per_em);
                    try simple.addImplicitPoints(allocator);
                    simple.scale(0.7);
                    simple.translate(gm.Vec2{ 0.2, 0.2 });
                    var dists = try SdfIterator.init(allocator, g.simple, @floatFromInt(width), @floatFromInt(height));
                    defer dists.deinit();

                    while (dists.next()) |min_dist| {
                        buffer[dists.curr_pos[1] * atlas_w + dists.curr_pos[0] + y * atlas_w * height + x * width] = min_dist;
                    }
                },
                else => return error.TodoCompoundGlyph,
            }
        }

        _ = try w.write(std.mem.sliceAsBytes(buffer));
        try w.flush();
    }

    const GlyphMap = std.StringArrayHashMap(gm.Vec2);
    pub fn glyphMap(self: Atlas, allocator: Allocator) !GlyphMap {
        const cols: f32 = @floatFromInt(self.width / self.glyph_width);
        const rows: f32 = @floatFromInt(self.height / self.glyph_height);
        const glyph_w: f32 = 1 / cols;
        const glyph_h: f32 = 1 / rows;

        var map = GlyphMap.init(allocator);
        try map.ensureTotalCapacity(self.num_glyphs);
        var glyphs = (try std.unicode.Utf8View.init(self.glyphs)).iterator();
        var x: f32 = 0;
        var y: f32 = 0;

        while (glyphs.nextCodepointSlice()) |g| : (x += 1) {
            if (x == cols) {
                x = 0;
                y += 1;
            }

            map.putAssumeCapacity(g, gm.Vec2{ glyph_w * x, -glyph_h * y });
        }

        return map;
    }

    pub fn deinit(self: Atlas) void {
        self.allocator.free(self.data);
    }
};

pub const SdfIterator = struct {
    allocator: Allocator,
    sdf: gm.Sdf = gm.Sdf{},
    shape: gm.Shape,
    viewport: gm.Vec2,
    position: gm.Vec2 = gm.Vec2{ 0, 0 },
    i: usize = 0,
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

        std.debug.assert(min_dist >= -1 and min_dist <= 1);

        self.i = @intFromFloat(self.position[1] * self.viewport[0] + self.position[0]);
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
