const std = @import("std");
const zut = @import("zut");

const dbg = zut.dbg;
const Allocator = std.mem.Allocator;
const Vec2 = @import("zml").Vec2;
const BufStream = @import("zap").BufStream;
const GlyfTable = @import("tables/glyf.zig").GlyfTable;
const MaxpTable = @import("tables/maxp.zig").MaxpTable;

pub const CompoundGlyph = struct {
    allocator: Allocator,
    glyf: GlyfTable,
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

    pub fn parse(allocator: Allocator, glyf: *GlyfTable, maxp: MaxpTable) !CompoundGlyph {
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
            .components = try allocator.realloc(components, num_components),
        };
    }

    pub fn deinit(self: CompoundGlyph) void {
        self.allocator.free(self.components);
    }
};
