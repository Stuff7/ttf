const std = @import("std");
const zut = @import("zut");
const gm = @import("zml");

const dbg = zut.dbg;
const Allocator = std.mem.Allocator;
const Vec2 = @import("zml").Vec2;
const BufStream = @import("zap").BufStream;
const GlyphParser = @import("parser.zig").GlyphParser;
const SimpleGlyph = @import("simple_glyph.zig").SimpleGlyph;
const GlyfTable = @import("tables/glyf.zig").GlyfTable;
const MaxpTable = @import("tables/maxp.zig").MaxpTable;

pub const CompoundGlyph = struct {
    allocator: Allocator,
    glyf: GlyfTable,
    advance_width: f32,
    lsb: f32,
    components: []Component,

    const Flag = enum(u16) {
        arg_1_and_2_are_words = 1,
        we_have_a_scale = 1 << 3,
        more_components = 1 << 5,
        we_have_an_x_and_y_scale = 1 << 6,
        we_have_a_two_by_two = 1 << 7,
        we_have_instructions = 1 << 8,
    };

    const Component = struct {
        idx: u16,
        pos: Vec2,
    };

    pub fn parse(allocator: Allocator, glyf: *GlyfTable, maxp: MaxpTable, advance_width: f32, lsb: f32) !CompoundGlyph {
        var flags: u16 = 0;
        var num_components: usize = 0;
        const components = try allocator.alloc(Component, maxp.max_component_elements);

        while (true) {
            flags = try glyf.glyph_stream.readAs(u16);
            const component = &components[num_components];
            component.idx = try glyf.glyph_stream.readAs(u16);
            try dbg.rtAssertFmt(
                component.idx < maxp.num_glyphs,
                "Invalid glyph id\n  Expected: < {}\n  Received: {}",
                .{ maxp.num_glyphs, component.idx },
            );
            try dbg.rtAssertFmt(
                num_components < maxp.max_component_elements,
                "num_components exceeds maxp.max_component_elements {}",
                .{maxp.max_component_elements},
            );
            num_components += 1;

            if (zut.mem.enumMask(flags, Flag.arg_1_and_2_are_words)) {
                const argument1 = try glyf.glyph_stream.readAs(i16);
                const argument2 = try glyf.glyph_stream.readAs(i16);
                component.pos[0] = @floatFromInt(argument1);
                component.pos[1] = @floatFromInt(argument2);
            } else {
                const argument1 = try glyf.glyph_stream.readU8();
                const argument2 = try glyf.glyph_stream.readU8();
                component.pos[0] = @floatFromInt(argument1);
                component.pos[1] = @floatFromInt(argument2);
            }

            if (zut.mem.enumMask(flags, Flag.we_have_a_scale)) {
                _ = try glyf.glyph_stream.readAs(i16); // scale
            } else if (zut.mem.enumMask(flags, Flag.we_have_an_x_and_y_scale)) {
                _ = try glyf.glyph_stream.readAs(i16); // xscale
                _ = try glyf.glyph_stream.readAs(i16); // yscale
            } else if (zut.mem.enumMask(flags, Flag.we_have_a_two_by_two)) {
                _ = try glyf.glyph_stream.readAs(i16); // xscale
                _ = try glyf.glyph_stream.readAs(i16); // scale10
                _ = try glyf.glyph_stream.readAs(i16); // scale01
                _ = try glyf.glyph_stream.readAs(i16); // yscale
            }
            if (!zut.mem.enumMask(flags, Flag.more_components)) {
                break;
            }
        }

        if (zut.mem.enumMask(flags, Flag.we_have_instructions)) {
            const instructions_length = try glyf.glyph_stream.readAs(u16);

            if (maxp.major == 1) {
                try dbg.rtAssertFmt(
                    maxp.max_size_of_instructions >= instructions_length,
                    "Instructions length exceeds maxp.max_size_of_instructions {}: {}",
                    .{ maxp.max_size_of_instructions, instructions_length },
                );
            }

            try glyf.glyph_stream.skip(instructions_length);
        }

        return CompoundGlyph{
            .allocator = allocator,
            .glyf = glyf.*,
            .advance_width = advance_width,
            .lsb = lsb,
            .components = try allocator.realloc(components, num_components),
        };
    }

    /// Merge compound glyph components into a simple glyph.
    /// Caller **must only free the returned simple glyph**.
    /// Calling `CompoundGlyph.deinit` after calling this function is **undefined behavior**
    pub fn simplify(self: CompoundGlyph, parser: *GlyphParser) !SimpleGlyph {
        const glyphs = try self.allocator.alloc(SimpleGlyph, self.components.len);

        defer self.allocator.free(glyphs);

        var num_points: usize = 0;
        var num_contours: usize = 0;

        for (self.components, glyphs) |c, *g| {
            g.* = (try parser.getGlyphById(self.allocator, c.idx)).simple;
            num_points += g.points.len;
            num_contours += g.end_pts_of_contours.len;
        }
        dbg.dump(glyphs);

        defer for (glyphs) |gl| {
            gl.deinit();
        };

        var simple = SimpleGlyph{
            .allocator = self.allocator,
            .glyf = self.glyf,
            .advance_width = self.advance_width,
            .lsb = self.lsb,
            .points = try self.allocator.alloc(gm.Vec2, num_points),
            .curve_flags = try self.allocator.alloc(bool, num_points),
            .end_pts_of_contours = try self.allocator.alloc(u16, num_contours),
        };

        simple.glyf.number_of_contours = @intCast(num_contours);

        var prev_g: ?SimpleGlyph = null;
        var offset_points: usize = 0;
        var offset_contours: usize = 0;

        for (glyphs, self.components) |g, component| {
            if (prev_g) |pg| {
                offset_points += pg.points.len;
                offset_contours += pg.end_pts_of_contours.len;
            }

            for (g.points, offset_points..) |p, j| {
                simple.points[j] = p + component.pos;
            }

            @memcpy(simple.curve_flags[offset_points .. offset_points + g.curve_flags.len], g.curve_flags);

            if (prev_g) |_| {
                for (g.end_pts_of_contours, offset_contours..) |c, j| {
                    simple.end_pts_of_contours[j] = @intCast(c + offset_points);
                }
            } else {
                @memcpy(simple.end_pts_of_contours[0..g.end_pts_of_contours.len], g.end_pts_of_contours);
            }

            prev_g = g;
        }
        defer self.allocator.free(self.components);

        return simple;
    }

    pub fn deinit(self: CompoundGlyph) void {
        self.allocator.free(self.components);
    }
};
