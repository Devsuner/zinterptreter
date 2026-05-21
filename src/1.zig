const std = @import("std");
const lexer = @import("./lexer.zig");
const parser = @import("./parser.zig");

const PROMPT = ">> ";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    _ = io;

    std.debug.print("Hello! This is the Monkey programming language!\n", .{});
    std.debug.print("Feel free to type in commands\n", .{});

    const stdin_fd = std.posix.STDIN_FILENO;
    var buffer: [4096]u8 = undefined;

    while (true) {
        std.debug.print("{s}", .{PROMPT});

        const n = std.posix.read(stdin_fd, &buffer) catch |err| {
            std.debug.print("Read error: {any}\n", .{err});
            continue;
        };
        if (n == 0) break;
        const line = std.mem.trimEnd(u8, buffer[0..n], "\r\n");

        var my_lexer = lexer.Lexer.init(line);
        const tokens = my_lexer.nextToken(gpa) catch |err| {
            std.debug.print("Lexer error: {any}\n", .{err});
            continue;
        };
        defer gpa.free(tokens);

        var my_parser = parser.Parser.init(tokens, gpa);
        defer my_parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(gpa);
        defer ast_arena.deinit();

        const program = my_parser.parseProgram(ast_arena.allocator()) catch |err| {
            std.debug.print("Parser error: {any}\n", .{err});
            continue;
        };

        if (my_parser.errors.items.len > 0) {
            printParserErrors(my_parser.errors.items);
            continue;
        }

        const output = program.string(gpa) catch |err| {
            std.debug.print("String error: {any}\n", .{err});
            continue;
        };
        defer gpa.free(output);
        std.debug.print("{s}\n", .{output});
    }
}

fn printParserErrors(errors: []const []const u8) void {
    std.debug.print(
        \\
        \\            __,__
        \\   .--.  .-"     "-.  .--.
        \\  / .. \/  .-. .-.  \/ .. \
        \\ | |  '|  /   Y   \  |'  | |
        \\ | \   \  \ 0 | 0 /  /   / |
        \\  \ '- ,\.-"""""""-./, -' /
        \\   ''-' /_   ^ ^   _\ '-''
        \\       |  \._   _./  |
        \\       \   \ '~' /   /
        \\        '._ '-=-' _.'
        \\           '-----'
        \\
    , .{});
    std.debug.print("Woops! We ran into some monkey business here!\n", .{});
    std.debug.print(" parser errors:\n", .{});
    for (errors) |msg| {
        std.debug.print("\t{s}\n", .{msg});
    }
}
