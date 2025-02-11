const dbg = @import("dbgutils");
const BufStream = @import("../bufstream.zig").BufStream;

pub const HeadTable = struct {
    major_version: u16,
    minor_version: u16,
    font_revision: i32,
    checksum_adjustment: u32,
    flags: u16,
    units_per_em: f32,
    created: i64,
    modified: i64,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: u16,
    lowest_rec_ppem: u16,
    font_direction_hint: i16,
    index_to_loc_format: LocFormat,
    glyph_data_format: i16,

    pub fn parse(bs: *BufStream) !HeadTable {
        const major_version = try bs.readAs(u16);
        const minor_version = try bs.readAs(u16);
        const font_revision = try bs.readAs(i32);
        const checksum_adjustment = try bs.readAs(u32);
        const magic_number = try bs.readAs(u32);

        try dbg.rtAssertFmt(
            magic_number == 0x5F0F3CF5,
            "Invalid magic number\n  Expected: 0x5F0F3CF5\n  Received: {X}",
            .{magic_number},
        );

        return HeadTable{
            .major_version = major_version,
            .minor_version = minor_version,
            .font_revision = font_revision,
            .checksum_adjustment = checksum_adjustment,
            .flags = try bs.readAs(u16),
            .units_per_em = @floatFromInt(try bs.readAs(u16)),
            .created = try bs.readAs(i64),
            .modified = try bs.readAs(i64),
            .x_min = try bs.readAs(i16),
            .y_min = try bs.readAs(i16),
            .x_max = try bs.readAs(i16),
            .y_max = try bs.readAs(i16),
            .mac_style = try bs.readAs(u16),
            .lowest_rec_ppem = try bs.readAs(u16),
            .font_direction_hint = try bs.readAs(i16),
            .index_to_loc_format = @enumFromInt(try bs.readAs(i16)),
            .glyph_data_format = try bs.readAs(i16),
        };
    }
};

const LocFormat = enum {
    short,
    long,
};
