const std = @import("std");

pub usingnamespace @import("parser.zig");
pub usingnamespace @import("simple_glyph.zig");
pub usingnamespace @import("compound_glyph.zig");
pub usingnamespace @import("tables/dec.zig");
pub usingnamespace @import("tables/name.zig");
pub usingnamespace @import("tables/head.zig");
pub usingnamespace @import("tables/hmtx.zig");
pub usingnamespace @import("tables/hhea.zig");
pub usingnamespace @import("tables/cmap.zig");
pub usingnamespace @import("tables/loca.zig");
pub usingnamespace @import("tables/glyf.zig");
pub usingnamespace @import("tables/maxp.zig");

const dbg = @import("zut").dbg;
const BufStream = @import("bufstream.zig").BufStream;

pub const Ttf = struct {
    sfnt_version: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
    table_records: [@intFromEnum(TableTag.unknown)]TableRecord,
    bs: *BufStream,

    pub fn parse(bs: *BufStream) !Ttf {
        const sfnt_version = try bs.readAs(u32);
        try dbg.rtAssertFmt(
            sfnt_version == 0x00010000 or sfnt_version == 0x4F54544F,
            "Invalid sfnfVersion\n  Expected: 0x00010000 | 0x4F54544F\n  Received: 0x{X}",
            .{sfnt_version},
        );

        const num_tables = try bs.readAs(u16);
        const search_range = try bs.readAs(u16);
        const entry_selector = try bs.readAs(u16);
        const range_shift = try bs.readAs(u16);

        var table_records: [@intFromEnum(TableTag.unknown)]TableRecord = undefined;
        for (0..num_tables) |_| {
            const tag = try TableTag.parse(bs);
            if (tag == TableTag.unknown) {
                try bs.skip(@sizeOf(TableRecord));
                continue;
            }
            table_records[@intFromEnum(tag)] = try TableRecord.parse(bs);
        }

        return Ttf{
            .sfnt_version = sfnt_version,
            .num_tables = num_tables,
            .search_range = search_range,
            .entry_selector = entry_selector,
            .range_shift = range_shift,
            .table_records = table_records,
            .bs = bs,
        };
    }

    pub fn findTable(self: Ttf, tag: TableTag) !BufStream {
        const record = self.table_records[@intFromEnum(tag)];
        if (record.length > 0) {
            return try self.bs.slice(record.offset, record.length);
        }
        return error.TableNotFound;
    }
};

const TableTag = enum(u8) {
    gdef,
    gpos,
    gsub,
    os2,
    cmap,
    cvt,
    fpgm,
    gasp,
    head,
    loca,
    maxp,
    name,
    hmtx,
    hhea,
    glyf,
    unknown,

    pub fn parse(bs: *BufStream) !TableTag {
        var tag: [4:0]u8 = undefined;
        try bs.readTo(&tag);

        if (std.mem.eql(u8, &tag, "GDEF")) {
            return .gdef;
        } else if (std.mem.eql(u8, &tag, "GPOS")) {
            return .gpos;
        } else if (std.mem.eql(u8, &tag, "GSUB")) {
            return .gsub;
        } else if (std.mem.eql(u8, &tag, "OS/2")) {
            return .os2;
        } else if (std.mem.eql(u8, &tag, "cmap")) {
            return .cmap;
        } else if (std.mem.eql(u8, &tag, "cvt ")) {
            return .cvt;
        } else if (std.mem.eql(u8, &tag, "fpgm")) {
            return .fpgm;
        } else if (std.mem.eql(u8, &tag, "gasp")) {
            return .gasp;
        } else if (std.mem.eql(u8, &tag, "head")) {
            return .head;
        } else if (std.mem.eql(u8, &tag, "loca")) {
            return .loca;
        } else if (std.mem.eql(u8, &tag, "maxp")) {
            return .maxp;
        } else if (std.mem.eql(u8, &tag, "name")) {
            return .name;
        } else if (std.mem.eql(u8, &tag, "hmtx")) {
            return .hmtx;
        } else if (std.mem.eql(u8, &tag, "hhea")) {
            return .hhea;
        } else if (std.mem.eql(u8, &tag, "glyf")) {
            return .glyf;
        }

        dbg.warn("Unknown table record {s}", .{tag});
        return TableTag.unknown;
    }
};

const TableRecord = struct {
    checksum: u32,
    offset: u32,
    length: u32,

    pub fn parse(bs: *BufStream) !TableRecord {
        return .{
            .checksum = try bs.readAs(u32),
            .offset = try bs.readAs(u32),
            .length = try bs.readAs(u32),
        };
    }
};

pub fn mask(flag: anytype, bitmask: anytype) bool {
    return (flag & bitmask) == bitmask;
}

pub fn enumMask(flag: anytype, bitmask: anytype) bool {
    return mask(flag, @intFromEnum(bitmask));
}
