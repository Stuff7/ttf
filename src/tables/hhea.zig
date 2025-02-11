const BufStream = @import("../bufstream.zig").BufStream;

pub const HheaTable = struct {
    major_version: u16,
    minor_version: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    advance_width_max: u16,
    min_left_side_bearing: i16,
    min_right_side_bearing: i16,
    x_max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    metric_data_format: i16,
    number_of_hMetrics: u16,

    pub fn parse(bs: *BufStream) !HheaTable {
        return HheaTable{
            .major_version = try bs.readAs(u16),
            .minor_version = try bs.readAs(u16),
            .ascender = try bs.readAs(i16),
            .descender = try bs.readAs(i16),
            .line_gap = try bs.readAs(i16),
            .advance_width_max = try bs.readAs(u16),
            .min_left_side_bearing = try bs.readAs(i16),
            .min_right_side_bearing = try bs.readAs(i16),
            .x_max_extent = try bs.readAs(i16),
            .caret_slope_rise = try bs.readAs(i16),
            .caret_slope_run = try bs.readAs(i16),
            .caret_offset = try bs.readAs(i16),
            .metric_data_format = ret: {
                try bs.skip(4 * @sizeOf(i16)); // RESERVED
                break :ret try bs.readAs(i16);
            },
            .number_of_hMetrics = try bs.readAs(u16),
        };
    }
};
