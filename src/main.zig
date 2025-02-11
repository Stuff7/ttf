const std = @import("std");
const gm = @import("zml");
const dbg = @import("dbgutils");
const ttf = @import("ttf");
const utf8 = @import("utf8utils");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 2) {
        dbg.usage(args[0], .{ "<path>", "Path to ttf file" });
        return;
    }

    var parser = try ttf.GlyphParser.parse(allocator, args[1]);
    dbg.dump(parser);

    var b = try parser.font.findTable(.name);
    var name = try ttf.NameTable.parse(allocator, &b);
    dbg.dump(name);

    const fmt = comptime utf8.esc("1") ++ utf8.clr("122") ++ "{}|{}: " ++ utf8.esc("0") ++ utf8.clr("214") ++ "{s}\n" ++ utf8.esc("0");
    for (name.name_record) |record| {
        const s = try record.value(allocator, &name);
        defer allocator.free(s);
        std.debug.print(fmt, .{ record.platform_id, record.name_id, s });
    }

    std.debug.print("\n", .{});
}
