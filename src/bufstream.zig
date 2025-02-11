const std = @import("std");
const dbg = @import("dbgutils");

pub const BufStream = struct {
    buf: []u8,
    i: usize = 0,

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !BufStream {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        return BufStream{
            .buf = try file.readToEndAlloc(allocator, 100e6),
        };
    }

    pub fn slice(self: BufStream, offset: usize, size: usize) !BufStream {
        try dbg.rtAssertFmt(
            offset + size <= self.buf.len,
            "BufStream[{*}] slice out of bounds\n  Slice: (offset){} + (size){} = {} > {}",
            .{ self.buf, offset, size, offset + size, self.buf.len },
        );

        return BufStream{ .buf = self.buf[offset .. offset + size] };
    }

    pub fn skip(self: *BufStream, bytes: usize) !void {
        const i = self.i + bytes;

        try dbg.rtAssertFmt(
            i < self.buf.len,
            "BufStream[{*}] skip out of bound\n (pos){} + (skip){} = {} >= {}",
            .{ self.buf, self.i, bytes, self.i + bytes, self.buf.len },
        );

        self.i = i;
    }

    pub fn readU8(self: *BufStream) !u8 {
        try dbg.rtAssertFmt(
            self.i < self.buf.len,
            "BufStream[{*}] readU8 out of bounds\n  (pos){} + 1 byte = {} == {}",
            .{ self.buf, self.i, self.i + 1, self.buf.len },
        );

        const ret = self.buf[self.i];
        self.i += 1;
        return ret;
    }

    pub fn readAs(self: *BufStream, comptime T: type) !T {
        const bytes = @sizeOf(T);
        const start = self.i;
        self.i += bytes;

        try dbg.rtAssertFmt(
            self.i <= self.buf.len,
            "BufStream[{*}] readAs out of bounds\n  (pos){} + (bytes){} = {} > {}",
            .{ self.buf, self.i, bytes, self.i + bytes, self.buf.len },
        );

        return std.mem.readInt(T, self.buf[start .. start + bytes][0..bytes], .big);
    }

    pub fn readTo(self: *BufStream, out: []u8) !void {
        const bytes = out.len;
        const start = self.i;
        self.i += bytes;

        try dbg.rtAssertFmt(
            self.i <= self.buf.len,
            "BufStream[{*}] readTo out of bounds\n  (pos){} + (bytes){} = {} > {}",
            .{ self.buf, self.i, bytes, self.i + bytes, self.buf.len },
        );

        @memcpy(out, self.buf[start .. start + bytes]);
    }
};
