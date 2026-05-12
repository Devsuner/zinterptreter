const std = @import("std");
const lexer = @import("./lexer.zig");
const token = @import("./token.zig");
const print = std.debug.print;
const PROMOT = ">>";
pub fn start(gpa: std.mem.Allocator, io: std.Io, buffer: []u8) !void {
    var stdin = std.Io.File.stdin();
    // var stdout = std.Io.File.stdout();

    // var wt_buf: [4096]u8 = undefined;
    var freader = stdin.reader(io, buffer);
    // var fwriter = stdout.writer(io, wt_buf[0..]);

    const reader = &freader.interface;
    // const writer = &fwriter.interface;

    while (true) {
        print("{s}", .{PROMOT});

        const line = try reader.takeDelimiter('\n') orelse break;
        std.debug.print("line:{s}\n", .{line});
        // try writer.flush();
        var Lexer = lexer.Lexer.init(line);
        const token_list = Lexer.nextToken(gpa) catch |err| {
            print("Lexer error: {any}\n", .{err});
            continue;
        };
        for (token_list) |value| {
            print("Type: {any}, Literal: {s}\n", .{ value.Type, value.Literal });
        }
        gpa.free(token_list);
    }
}
