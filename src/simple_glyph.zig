const std = @import("std");
const gm = @import("zml");

const dbg = @import("zut").dbg;
const BufStream = @import("bufstream.zig").BufStream;
const GlyfTable = @import("tables/glyf.zig").GlyfTable;
const MaxpTable = @import("tables/maxp.zig").MaxpTable;
const mask = @import("ttf.zig").mask;

pub const SimpleGlyph = struct {
    glyf: GlyfTable,
    points: []gm.Vec2,
    curve_flags: []bool,
    advance_width: f32,
    lsb: f32,
    end_pts_of_contours: []u16,

    const Flag = enum(u8) {
        const curve: u8 = 1;
        const u8_x: u8 = 1 << 1;
        const u8_y: u8 = 1 << 2;
        const repeat: u8 = 1 << 3;
        const instruction_x: u8 = 1 << 4;
        const instruction_y: u8 = 1 << 5;
        const overlap_simple: u8 = 1 << 6;
        const reserved_bit: u8 = 1 << 7;
    };

    pub fn parse(allocator: std.mem.Allocator, glyf: *GlyfTable, maxp: MaxpTable, advance_width: f32, lsb: f32) !SimpleGlyph {
        const number_of_contours: usize = @intCast(glyf.number_of_contours);
        const end_pts_of_contours = try allocator.alloc(u16, number_of_contours);

        var num_points: usize = 0;
        for (0..number_of_contours) |i| {
            end_pts_of_contours[i] = try glyf.glyph_stream.readAs(u16);
            try dbg.rtAssertFmt(
                end_pts_of_contours[i] != 0xFFFF,
                "Invalid end_pts_of_contour [{} / {}]",
                .{ i, glyf.number_of_contours },
            );
            try dbg.rtAssertFmt(
                end_pts_of_contours[i] >= num_points,
                "Decreasing end_pts_of_contour [{} / {}]",
                .{ i, glyf.number_of_contours },
            );

            num_points = end_pts_of_contours[i];
        }
        num_points += 1;

        const instructions_length = try glyf.glyph_stream.readAs(u16);

        if (maxp.major == 1) {
            try dbg.rtAssertFmt(
                num_points <= maxp.max_points,
                "num_points exceeds maxp.max_points\n  num_points: {}\n  max_points: {}",
                .{ num_points, maxp.max_points },
            );
            try dbg.rtAssertFmt(
                maxp.max_size_of_instructions >= instructions_length,
                "instructions_length exceeds maxp.max_size_of_instructions\n  instructions_length: {}\n  max_size_of_instructions: {}",
                .{ instructions_length, maxp.max_size_of_instructions },
            );
        }

        try glyf.glyph_stream.skip(instructions_length);
        const flags = try allocator.alloc(u8, num_points);

        var flag: u8 = 0;
        var repeat: u8 = 0;
        var i: usize = 0;
        while (i < num_points) {
            flag = try glyf.glyph_stream.readU8();

            try dbg.rtAssertFmt(
                (!mask(flag, Flag.overlap_simple) or i == 0) and !mask(flag, Flag.reserved_bit),
                "OVERLAP_SIMPLE (bit 6) and RESERVED (bit 7) must be 0 in flag 0b{b:0>8} [{} / {}]",
                .{ flag, i, num_points },
            );

            flags[i] = flag & ~Flag.repeat;

            if (mask(flag, Flag.repeat)) {
                repeat = try glyf.glyph_stream.readU8();
                try dbg.rtAssertFmt(
                    repeat != 0,
                    "Repeat is 0 in flag 0b{b:0>8} [{} / {}]",
                    .{ flag, i, num_points },
                );

                try dbg.rtAssertFmt(
                    i + repeat < num_points,
                    "Repeat {} exceeds num_points {} in flag 0b{b:0>8} [{} / {}]",
                    .{ repeat, num_points, flag, i, num_points },
                );

                while (repeat > 0) {
                    i += 1;
                    flags[i] = flag & ~Flag.repeat;
                    repeat -= 1;
                }
            }
            i += 1;
        }

        const points = try allocator.alloc(gm.Vec2, num_points);
        const curve_flags = try allocator.alloc(bool, num_points);
        try SimpleGlyph.parsePoints(flags, points, curve_flags, &glyf.glyph_stream, true);
        try SimpleGlyph.parsePoints(flags, points, curve_flags, &glyf.glyph_stream, false);
        allocator.free(flags);
        glyf.glyph_stream.i = 0;

        return SimpleGlyph{
            .glyf = glyf.*,
            .points = points,
            .curve_flags = curve_flags,
            .advance_width = advance_width,
            .lsb = lsb,
            .end_pts_of_contours = end_pts_of_contours,
        };
    }

    pub fn parsePoints(flags: []u8, points: []gm.Vec2, curve_flags: []bool, bs: *BufStream, is_x: bool) !void {
        const u8mask: u8 = if (is_x) Flag.u8_x else Flag.u8_y;
        const instruction_mask: u8 = if (is_x) Flag.instruction_x else Flag.instruction_y;
        var coord: i16 = 0;

        for (flags, points, curve_flags) |flag, *point, *on_curve| {
            if (mask(flag, u8mask)) {
                const offset: i16 = @intCast(try bs.readU8());
                coord += if (mask(flag, instruction_mask)) offset else -offset;
            } else if (!mask(flag, instruction_mask)) {
                const delta = try bs.readAs(i16);
                coord += delta;
            }

            if (is_x) {
                point[0] = @floatFromInt(coord);
            } else {
                point[1] = @floatFromInt(coord);
            }

            on_curve.* = mask(flag, Flag.curve);
        }
    }

    pub fn addImplicitPoints(self: *SimpleGlyph, allocator: std.mem.Allocator) !void {
        var total_points = self.points.len;
        var consecutive_off_curve = false;
        for (0..self.points.len) |n| {
            if (consecutive_off_curve and !self.curve_flags[n]) {
                total_points += 1;
            }
            consecutive_off_curve = !self.curve_flags[n];
        }

        if (total_points == self.points.len) {
            return;
        }

        const points = try allocator.alloc(gm.Vec2, total_points);
        const on_curve = try allocator.alloc(bool, total_points);
        const number_of_contours: usize = @intCast(self.glyf.number_of_contours);
        const end_pts_of_contours = try allocator.alloc(u16, number_of_contours);
        @memcpy(end_pts_of_contours, self.end_pts_of_contours);

        const tolerance = gm.vec2.fill(1e-3);
        var num_points: usize = 0;
        var contour_idx: usize = 0;
        var contour_start: usize = 0;
        var contour_end = self.end_pts_of_contours[contour_idx];
        var curr_idx: usize = 0;

        while (curr_idx < self.points.len) : (curr_idx += 1) {
            if (curr_idx > contour_end) {
                contour_start = contour_end + 1;
                contour_idx += 1;
                if (contour_idx < self.glyf.number_of_contours) {
                    contour_end = self.end_pts_of_contours[contour_idx];
                }
            }
            const next_idx = if (curr_idx == contour_end) contour_start else curr_idx + 1;

            const curr_point = self.points[curr_idx];
            const curr_on_curve = self.curve_flags[curr_idx];
            const next_on_curve = self.curve_flags[next_idx];

            points[num_points] = curr_point;
            on_curve[num_points] = curr_on_curve;
            num_points += 1;
            if (num_points == total_points) {
                break;
            }

            if (!curr_on_curve and !next_on_curve) {
                const next_point = self.points[next_idx];
                const p = gm.vec2.lerp(curr_point, next_point, 0.5);
                if (gm.vec2.lt(@abs(p - next_point), tolerance)) {
                    for (contour_idx..number_of_contours) |i| {
                        end_pts_of_contours[i] -= 1;
                    }
                    curr_idx += 1;
                    dbg.print("SKIP", .{});
                    continue;
                }
                points[num_points] = p;
                on_curve[num_points] = true;
                num_points += 1;
                for (contour_idx..number_of_contours) |i| {
                    end_pts_of_contours[i] += 1;
                }
            }
        }

        allocator.free(self.points);
        allocator.free(self.end_pts_of_contours);
        if (total_points != num_points) {
            self.points = try allocator.realloc(points, num_points);
            self.curve_flags = try allocator.realloc(on_curve, num_points);
        } else {
            self.points = points;
            self.curve_flags = on_curve;
        }
        self.end_pts_of_contours = end_pts_of_contours;
    }

    pub fn normalizeEm(self: *SimpleGlyph, units_per_em: f32) void {
        const bbox = gm.vec2.fill(units_per_em);
        for (self.points) |*p| {
            p.* = (p.* - self.glyf.min) / bbox;
        }

        self.advance_width /= units_per_em;
        self.lsb /= units_per_em;
        self.glyf.max = (self.glyf.max + self.glyf.min) / bbox;
        self.glyf.min = gm.vec2.fill(0);
    }

    pub fn normalize(self: *SimpleGlyph) void {
        const bbox = self.glyf.max - self.glyf.min;
        const max_dim = gm.vec2.fill(@max(bbox[0], bbox[1]));
        for (self.points) |*p| {
            p.* = (p.* - self.glyf.min) / max_dim;
        }

        self.glyf.min = gm.vec2.fill(0);
        self.glyf.max = bbox / max_dim;
    }

    pub fn center(self: *SimpleGlyph, top_right: gm.Vec2) void {
        const vsize = self.glyf.max - self.glyf.min;
        const vhalf = gm.vec2.scale(top_right, 0.5);
        self.glyf.min = vhalf - gm.vec2.scale(vsize, 0.5) - self.glyf.min;
        self.glyf.max = self.glyf.min + vsize;

        for (self.points) |*p| {
            p.* += self.glyf.min;
        }
    }

    pub fn translate(self: *SimpleGlyph, d: gm.Vec2) void {
        for (self.points) |*p| {
            p.* += d;
        }
    }

    pub fn scale(self: *SimpleGlyph, s: f32) void {
        const vs = gm.vec2.fill(s);
        self.glyf.min *= vs;
        self.glyf.max *= vs;
        self.lsb *= s;
        self.advance_width *= s;

        for (self.points) |*p| {
            p.* *= vs;
        }
    }
};
