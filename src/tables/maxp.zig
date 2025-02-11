const BufStream = @import("../bufstream.zig").BufStream;

pub const MaxpTable = struct {
    major: u8,
    minor: u8,
    num_glyphs: u16,
    // Version 1.0
    max_points: u16 = 0,
    max_contours: u16 = 0,
    max_composite_points: u16 = 0,
    max_composite_contours: u16 = 0,
    max_zones: u16 = 0,
    max_twilight_points: u16 = 0,
    max_storage: u16 = 0,
    max_function_defs: u16 = 0,
    max_instruction_defs: u16 = 0,
    max_stack_elements: u16 = 0,
    max_size_of_instructions: u16 = 0,
    max_component_elements: u16 = 0,
    max_component_depth: u16 = 0,

    pub fn parse(bs: *BufStream) !MaxpTable {
        const version = try bs.readAs(u32);
        var self = MaxpTable{
            .major = @intCast(version >> 16),
            .minor = @intCast(version << 16 >> 16),
            .num_glyphs = try bs.readAs(u16),
        };

        if (self.major == 1) {
            self.max_points = try bs.readAs(u16);
            self.max_contours = try bs.readAs(u16);
            self.max_composite_points = try bs.readAs(u16);
            self.max_composite_contours = try bs.readAs(u16);
            self.max_zones = try bs.readAs(u16);
            self.max_twilight_points = try bs.readAs(u16);
            self.max_storage = try bs.readAs(u16);
            self.max_function_defs = try bs.readAs(u16);
            self.max_instruction_defs = try bs.readAs(u16);
            self.max_stack_elements = try bs.readAs(u16);
            self.max_size_of_instructions = try bs.readAs(u16);
            self.max_component_elements = try bs.readAs(u16);
            self.max_component_depth = try bs.readAs(u16);
        }

        return self;
    }
};
