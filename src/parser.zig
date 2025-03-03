const std = @import("std");

const dbg = @import("zut").dbg;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Ttf = @import("ttf.zig").Ttf;
const BufStream = @import("zap").BufStream;
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
    arena: ArenaAllocator,
    font: Ttf,
    head: HeadTable,
    maxp: MaxpTable,
    hhea: HheaTable,
    loca: LocaTable,
    hmtx: HmtxTable,
    cmap: CmapTable,
    null_glyph: Glyph,
    glyph_stream: BufStream,

    /// Returned parser must be freed calling `GlyphParser.deinit`
    pub fn parse(a: Allocator, path: []const u8) !GlyphParser {
        var arena = ArenaAllocator.init(a);
        const allocator = arena.allocator();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

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
            .arena = arena,
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

    /// Returned glyph must be freed calling `Glyph.deinit` **unless stated otherwise**
    pub fn getGlyph(self: *GlyphParser, allocator: Allocator, c: u21) !Glyph {
        const id = try self.cmap.subtable.findGlyphId(self.maxp.num_glyphs, c);
        dbg.print("Glyph: '{u}' ID: {}", .{ c, id });
        return self.getGlyphById(allocator, id) catch {
            return self.null_glyph;
        };
    }

    /// Returned glyph must be freed calling `Glyph.deinit` **unless stated otherwise**
    pub fn getGlyphById(self: *GlyphParser, allocator: Allocator, id: usize) !Glyph {
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

    pub fn deinit(self: GlyphParser) void {
        self.arena.deinit();
    }
};

pub const Glyph = union(enum(u1)) {
    simple: SimpleGlyph,
    compound: CompoundGlyph,

    /// Returned glyph must be freed calling `Glyph.deinit` **unless stated otherwise**
    pub fn parse(allocator: Allocator, bs: *BufStream, maxp: MaxpTable, advance_width: f32, lsb: f32) !Glyph {
        var glyf = try GlyfTable.parse(bs);

        if (glyf.number_of_contours >= 0) {
            return Glyph{
                .simple = try SimpleGlyph.parse(allocator, &glyf, maxp, advance_width, lsb),
            };
        } else {
            return Glyph{
                .compound = try CompoundGlyph.parse(allocator, &glyf, maxp, advance_width, lsb),
            };
        }
    }

    /// Merge compound glyph components into a simple glyph if the glyph is **not** simple already.
    /// Caller **must only free the returned simple glyph**, calling `Glyph.deinit` after calling this
    /// function is **undefined behavior**
    pub fn simplify(self: Glyph, parser: *GlyphParser) !SimpleGlyph {
        return switch (self) {
            .simple => |simple| simple,
            .compound => |compound| try compound.simplify(parser),
        };
    }

    pub fn deinit(self: Glyph) void {
        switch (self) {
            .simple => |g| g.deinit(),
            .compound => |g| g.deinit(),
        }
    }
};
