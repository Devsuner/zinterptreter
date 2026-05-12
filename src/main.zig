const std = @import("std");
const reql = @import("./repl.zig");
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    std.debug.print("Hello! This is the Monkey programming language!\n", .{});
    std.debug.print("Feel free to type in commands\n", .{});
    var buffer: [4096]u8 = undefined;
    try reql.start(gpa, io, buffer[0..buffer.len]);
}
