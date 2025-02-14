const std = @import("std");
const dec = @import("dec.zig");

const BufStream = @import("zap").BufStream;

pub const NameTable = struct {
    version: u16,
    storage_offset: u16,
    name_record: []NameRecord,
    lang_tag_record: ?[]LangTagRecord,
    bs: BufStream,

    pub fn parse(allocator: std.mem.Allocator, bs: *BufStream) !NameTable {
        const version = try bs.readAs(u16);
        const num_records = try bs.readAs(u16);
        const storage_offset = try bs.readAs(u16);

        const name_record = try allocator.alloc(NameRecord, num_records);
        for (name_record) |*record| {
            record.* = try NameRecord.parse(bs);
        }

        var lang_tag_record: ?[]LangTagRecord = null;
        if (version == 1) {
            lang_tag_record = try allocator.alloc(LangTagRecord, try bs.readAs(u16));
            for (lang_tag_record.?) |*record| {
                record.* = try LangTagRecord.parse(bs);
            }
        }

        return NameTable{
            .version = version,
            .storage_offset = storage_offset,
            .name_record = name_record,
            .lang_tag_record = lang_tag_record,
            .bs = try bs.slice(storage_offset, bs.buf.len - storage_offset),
        };
    }
};

const LangTagRecord = struct {
    length: u16,
    lang_tag_offset: u16,

    pub fn parse(bs: *BufStream) !LangTagRecord {
        return .{
            .length = try bs.readAs(u16),
            .lang_tag_offset = try bs.readAs(u16),
        };
    }
};

const NameRecord = struct {
    platform_id: dec.PlatformID,
    encoding_id: dec.EncodingID,
    language_id: u16,
    name_id: NameID,
    length: u16,
    string_offset: u16,

    pub fn parse(bs: *BufStream) !NameRecord {
        const platform_id = std.meta.intToEnum(dec.PlatformID, try bs.readAs(u16)) catch .unsupported;

        return NameRecord{
            .platform_id = platform_id,
            .encoding_id = try dec.EncodingID.parse(platform_id, bs),
            .language_id = try bs.readAs(u16),
            .name_id = std.meta.intToEnum(NameID, try bs.readAs(u16)) catch .unknown,
            .length = try bs.readAs(u16),
            .string_offset = try bs.readAs(u16),
        };
    }

    pub fn value(record: NameRecord, allocator: std.mem.Allocator, table: *NameTable) ![]u8 {
        var data = try table.bs.slice(record.string_offset, record.length);
        var str = try allocator.alloc(u8, record.length);

        if (record.platform_id == .windows and record.encoding_id.windows == .unicode_bmp) {
            try data.readTo(str);
            str = try dec.decodeUnicodeBMP(allocator, str);
        } else if (record.platform_id == .mac and record.encoding_id.mac == .roman) {
            try data.readTo(str);
            str = try dec.decodeMacRoman(allocator, str);
        } else {
            try data.readTo(str);
        }

        return str;
    }
};

const NameID = enum(u16) {
    copyright,
    font_family_name,
    font_sub_family_name,
    unique_font_identifier,
    full_font_name,
    version_string,
    post_script_name,
    trademark,
    manufacturer_name,
    designer,
    description,
    url_vendor,
    url_designer,
    license_description,
    license_info_url,
    reserved,
    typographic_family_name,
    typographic_subfamily_name,
    compatible_full,
    sample_text,
    post_script_cIDFind_font_name,
    w_wSFamily_name,
    w_wSSubfamily_name,
    light_background_palette,
    dark_background_palette,
    variations_post_script_name_prefix,
    unknown,
};
