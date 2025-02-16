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
const SdfIterator = @import("io.zig").SdfIterator;

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
            const g = try parser.getGlyph(allocator, c);
            var simple = try g.simplify(parser);
            defer simple.deinit();

            simple.normalizeEm(parser.head.units_per_em);
            try simple.addImplicitPoints(allocator);
            simple.scale(0.7);
            simple.translate(gm.Vec2{ 0.2, 0.2 });
            var dists = try SdfIterator.init(allocator, simple, @floatFromInt(width), @floatFromInt(height));
            defer dists.deinit();

            while (dists.next()) |min_dist| {
                buffer[dists.curr_pos[1] * atlas_w + dists.curr_pos[0] + y * atlas_w * height + x * width] = min_dist;
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
        self.allocator.free(self.glyphs);
        self.allocator.free(self.data);
    }
};
