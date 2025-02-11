const std = @import("std");

const BufStream = @import("../bufstream.zig").BufStream;
const HheaTable = @import("hhea.zig").HheaTable;
const MaxpTable = @import("maxp.zig").MaxpTable;

pub const HmtxTable = struct {
    h_metrics: []LongHorMetric,
    left_side_bearings: ?[]i16,

    pub const LongHorMetric = struct {
        advance_width: u16,
        lsb: i16,
    };

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream, hhea: HheaTable, maxp: MaxpTable) !HmtxTable {
        const h_metrics = try allocator.alloc(LongHorMetric, hhea.number_of_hMetrics);
        for (h_metrics) |*h_metric| {
            h_metric.advance_width = try bs.readAs(u16);
            h_metric.lsb = try bs.readAs(i16);
        }

        const left_side_bearings_size = maxp.num_glyphs - hhea.number_of_hMetrics;
        var left_side_bearings: ?[]i16 = null;
        if (left_side_bearings_size > 0) {
            left_side_bearings = try allocator.alloc(i16, left_side_bearings_size);
            for (left_side_bearings.?) |*bearing| {
                bearing.* = try bs.readAs(i16);
            }
        }

        return HmtxTable{
            .h_metrics = h_metrics,
            .left_side_bearings = left_side_bearings,
        };
    }
};
