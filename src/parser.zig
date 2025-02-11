const std = @import("std");
const dbg = @import("dbgutils");

const Ttf = @import("lib.zig").Ttf;
const BufStream = @import("bufstream.zig").BufStream;
const HeadTable = @import("tables/head.zig").HeadTable;
const MaxpTable = @import("tables/maxp.zig").MaxpTable;
const HheaTable = @import("tables/hhea.zig").HheaTable;
const LocaTable = @import("tables/loca.zig").LocaTable;
const HmtxTable = @import("tables/hmtx.zig").HmtxTable;
const CmapTable = @import("tables/cmap.zig").CmapTable;
const GlyfTable = @import("tables/glyf.zig").GlyfTable;
const SimpleGlyph = @import("simple_glyph.zig").SimpleGlyph;
const CompoundGlyph = @import("compound_glyph.zig").CompoundGlyph;

pub const GlyphParser = struct {
    font: Ttf,
    head: HeadTable,
    maxp: MaxpTable,
    hhea: HheaTable,
    loca: LocaTable,
    hmtx: HmtxTable,
    cmap: CmapTable,
    null_glyph: Glyph,
    glyph_stream: BufStream,

    pub fn parse(allocator: std.mem.Allocator, path: []const u8) !GlyphParser {
        var bs = try BufStream.fromFile(allocator, path);
        const font = try Ttf.parse(&bs);

        var b = try font.findTable(.head);
        const head = try HeadTable.parse(&b);

        b = try font.findTable(.maxp);
        const maxp = try MaxpTable.parse(&b);

        b = try font.findTable(.hhea);
        const hhea = try HheaTable.parse(&b);

        b = try font.findTable(.loca);
        const loca = try LocaTable.parse(allocator, &b, head, maxp);

        b = try font.findTable(.hmtx);
        const hmtx = try HmtxTable.parse(allocator, &b, hhea, maxp);

        b = try font.findTable(.cmap);
        const cmap = try CmapTable.parse(allocator, &b);

        var parser = GlyphParser{
            .font = font,
            .head = head,
            .maxp = maxp,
            .hhea = hhea,
            .loca = loca,
            .hmtx = hmtx,
            .cmap = cmap,
            .null_glyph = undefined,
            .glyph_stream = try font.findTable(.glyf),
        };

        parser.null_glyph = try parser.getGlyphById(allocator, 0);

        return parser;
    }

    pub fn getGlyph(self: *GlyphParser, allocator: std.mem.Allocator, c: u21) !Glyph {
        const id = try self.cmap.subtable.findGlyphId(self.maxp.num_glyphs, c);
        dbg.print("Glyph ID: {}", .{id});
        return self.getGlyphById(allocator, id) catch {
            return self.null_glyph;
        };
    }

    pub fn getGlyphById(self: *GlyphParser, allocator: std.mem.Allocator, id: usize) !Glyph {
        const offset = self.loca.offsets[id];
        const size = self.loca.offsets[id + 1] - offset;
        const advance_width, const lsb = if (id < self.hmtx.h_metrics.len)
            [2]f32{
                @floatFromInt(self.hmtx.h_metrics[id].advance_width),
                @floatFromInt(self.hmtx.h_metrics[id].lsb),
            }
        else
            [2]f32{
                @floatFromInt(self.hmtx.h_metrics[self.hmtx.h_metrics.len - 1].advance_width),
                @floatFromInt(self.hmtx.h_metrics[id - self.hmtx.h_metrics.len].lsb),
            };

        try dbg.rtAssertFmt(size > 0, "Glyph #{} is missing", .{id});
        var bs = try self.glyph_stream.slice(offset, self.glyph_stream.buf.len - offset);
        return try Glyph.parse(allocator, &bs, self.maxp, advance_width, lsb);
    }
};

pub const Glyph = union(enum(u1)) {
    simple: SimpleGlyph,
    compound: CompoundGlyph,

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream, maxp: MaxpTable, advance_width: f32, lsb: f32) !Glyph {
        var glyf = try GlyfTable.parse(bs);

        if (glyf.number_of_contours >= 0) {
            return Glyph{
                .simple = try SimpleGlyph.parse(allocator, &glyf, maxp, advance_width, lsb),
            };
        } else {
            return Glyph{
                .compound = try CompoundGlyph.parse(allocator, &glyf, maxp),
            };
        }
    }
};
