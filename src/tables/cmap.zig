const std = @import("std");
const dec = @import("dec.zig");

const dbg = @import("zut").dbg;
const BufStream = @import("zap").BufStream;
const HheaTable = @import("hhea.zig").HheaTable;
const MaxpTable = @import("maxp.zig").MaxpTable;

pub const CmapTable = struct {
    version: u16,
    num_tables: u16,
    encoding_records: []EncodingRecord,
    subtable: CmapSubtable,

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream) !CmapTable {
        const version = try bs.readAs(u16);
        try dbg.rtAssertFmt(
            version == 0,
            "Unsupported cmap version\n\rExpected: 0\n\tReceived: {}",
            .{version},
        );
        const num_tables = try bs.readAs(u16);

        const encoding_records = try allocator.alloc(EncodingRecord, num_tables);
        for (encoding_records) |*p| {
            p.* = try EncodingRecord.parse(bs);
        }

        const subtable_offset = CmapTable.findOffset(encoding_records) orelse 6490;
        var b = try bs.slice(subtable_offset, bs.buf.len - subtable_offset);

        return CmapTable{
            .version = version,
            .num_tables = num_tables,
            .encoding_records = encoding_records,
            .subtable = try CmapSubtable.parse(allocator, &b),
        };
    }

    pub fn findOffset(encoding_records: []EncodingRecord) ?usize {
        var found = false;
        for (encoding_records) |*record| {
            if (record.platform_id == .windows) {
                const encoding_id = record.encoding_id.windows;
                found =
                    (encoding_id == .symbol or encoding_id == .unicode_bmp or
                    encoding_id == .unicode_full);
            } else if (record.platform_id == .unicode) {
                const encoding_id = record.encoding_id.unicode;
                found =
                    (encoding_id == .id1_0 or encoding_id == .id1_1 or
                    encoding_id == .id2_0_bmp or encoding_id == .full);
            }

            if (found) {
                return record.subtable_offset;
            }
        }

        return null;
    }
};

pub const EncodingRecord = struct {
    platform_id: dec.PlatformID,
    encoding_id: dec.EncodingID,
    subtable_offset: u32,

    pub fn parse(bs: *BufStream) !EncodingRecord {
        const platform_id = std.meta.intToEnum(dec.PlatformID, try bs.readAs(u16)) catch .unsupported;
        return EncodingRecord{
            .platform_id = platform_id,
            .encoding_id = try dec.EncodingID.parse(platform_id, bs),
            .subtable_offset = try bs.readAs(u32),
        };
    }
};

// Format 4
pub const CmapSubtable = struct {
    format: u16,
    length: u16,
    language: u16,
    seg_count: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
    end_code: []u16,
    reserved_pad: u16,
    start_code: []u16,
    id_delta: []i16,
    id_range_offsets: []u16,
    glyph_id_stream: BufStream,

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream) !CmapSubtable {
        const format = try bs.readAs(u16);
        try dbg.rtAssertFmt(
            format == 4,
            "Unsupported cmap subtable format\n  Expected: 4\n  Received: {}",
            .{format},
        );

        const length = try bs.readAs(u16);
        try dbg.rtAssertFmt(
            length <= bs.buf.len,
            "cmap length exceeds bufstream size\n  BufStream: {}\n  Cmap: {}",
            .{ bs.buf.len, length },
        );

        const language = try bs.readAs(u16);
        const seg_count = try bs.readAs(u16) / 2;
        try dbg.rtAssertFmt(
            seg_count >= 1,
            "Invalid seg_count\n  Expected: >= 1\n  Received: {}",
            .{seg_count},
        );
        const search_range = try bs.readAs(u16);
        const entry_selector = try bs.readAs(u16);
        const range_shift = try bs.readAs(u16);

        const end_code = try allocator.alloc(u16, seg_count);
        for (end_code) |*p| {
            p.* = try bs.readAs(u16);
        }

        const reserved_pad = try bs.readAs(u16);
        try dbg.rtAssertFmt(
            reserved_pad == 0,
            "Unexpected cmap.reserved_pad value\n  Expected: 0\n  Received: {}",
            .{reserved_pad},
        );

        const start_code = try allocator.alloc(u16, seg_count);
        for (start_code) |*p| {
            p.* = try bs.readAs(u16);
        }

        const id_delta = try allocator.alloc(i16, seg_count);
        for (id_delta) |*p| {
            p.* = try bs.readAs(i16);
        }

        const glyph_id_stream = try bs.slice(bs.i, bs.buf.len - bs.i);
        const id_range_offsets = try allocator.alloc(u16, seg_count);
        for (id_range_offsets) |*p| {
            p.* = try bs.readAs(u16);
        }

        return CmapSubtable{
            .format = format,
            .length = length,
            .language = language,
            .seg_count = seg_count,
            .search_range = search_range,
            .entry_selector = entry_selector,
            .range_shift = range_shift,
            .end_code = end_code,
            .reserved_pad = reserved_pad,
            .start_code = start_code,
            .id_delta = id_delta,
            .id_range_offsets = id_range_offsets,
            .glyph_id_stream = glyph_id_stream,
        };
    }

    pub fn findGlyphId(self: *CmapSubtable, numGlyphs: usize, c: u21) !u16 {
        var glyph_id: u16 = 0;
        for (0..self.seg_count) |i| {
            if (c > self.end_code[i]) {
                continue;
            }
            if (c < self.start_code[i]) {
                break;
            }

            if (self.id_range_offsets[i] == 0) {
                var id: isize = @intCast(self.id_delta[i]);
                id += @intCast(c);
                id = @rem(id, 0x10000);
                glyph_id = @intCast(id);
            } else {
                var index: usize = @intCast(i);
                index = self.id_range_offsets[index] + (c - self.start_code[index] + index) * @sizeOf(u16);
                var bs = try self.glyph_id_stream.slice(index, self.glyph_id_stream.buf.len - index);
                glyph_id = try bs.readAs(u16);

                if (glyph_id != 0) {
                    var id: isize = @intCast(glyph_id);
                    id += @intCast(self.id_delta[i]);
                    id = id & 0xFFFF;
                    glyph_id = @intCast(id);
                }
            }
            try dbg.rtAssertFmt(
                glyph_id < numGlyphs,
                "Glyph ID out of range\n  glyphId: {}\n  char: {}",
                .{ glyph_id, c },
            );
            return glyph_id;
        }

        return 0;
    }
};
