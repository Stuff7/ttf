const Vec2 = @import("zml").Vec2;
const BufStream = @import("zap").BufStream;

pub const GlyfTable = struct {
    number_of_contours: isize,
    min: Vec2,
    max: Vec2,
    glyph_stream: BufStream,

    pub fn parse(bs: *BufStream) !GlyfTable {
        return GlyfTable{
            .number_of_contours = @intCast(try bs.readAs(i16)),
            .min = Vec2{ @floatFromInt(try bs.readAs(i16)), @floatFromInt(try bs.readAs(i16)) },
            .max = Vec2{ @floatFromInt(try bs.readAs(i16)), @floatFromInt(try bs.readAs(i16)) },
            .glyph_stream = try bs.slice(bs.i, bs.buf.len - bs.i),
        };
    }
};
