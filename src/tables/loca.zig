const std = @import("std");
const BufStream = @import("zap").BufStream;
const MaxpTable = @import("maxp.zig").MaxpTable;
const HeadTable = @import("head.zig").HeadTable;

pub const LocaTable = struct {
    offsets: []u32,

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream, head: HeadTable, maxp: MaxpTable) !LocaTable {
        const size = maxp.num_glyphs + 1;
        const self = LocaTable{
            .offsets = try allocator.alloc(u32, size),
        };

        if (head.index_to_loc_format == .short) {
            for (self.offsets) |*offset| {
                offset.* = @intCast(try bs.readAs(u16) * 2);
            }
        } else {
            for (self.offsets) |*offset| {
                offset.* = @intCast(try bs.readAs(u32));
            }
        }

        return self;
    }
};
