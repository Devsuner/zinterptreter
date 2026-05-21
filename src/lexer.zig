const token = @import("./token.zig");
const std = @import("std");

pub const Lexer = struct {
    const State = enum { start, int, indentifer };
    atPosition: u8,
    rdPosition: u8,
    ch: ?u8,
    source: []const u8,
    pub fn init(source: []const u8) Lexer {
        var l: Lexer = .{ .source = source, .atPosition = 0, .rdPosition = 0, .ch = 0 };
        l.readChar();
        return l;
    }
    pub fn nextToken(l: *Lexer, gpa: std.mem.Allocator) ![]token.Token {
        var list: std.ArrayList(token.Token) = .empty;
        state: switch (State.start) {
            .start => {
                if (l.ch == null) {
                    try list.append(gpa, .{ .Type = .eof, .Literal = "" });
                    break :state;
                }
                while (std.ascii.isWhitespace(l.ch.?)) {
                    l.readChar();
                }
                const start = l.atPosition;
                if (std.ascii.isDigit(l.ch.?)) {
                    continue :state .int;
                }
                if (std.ascii.isAlphabetic(l.ch.?) or (l.ch.? == '_')) {
                    continue :state .indentifer;
                }
                if (l.ch) |ch| {
                    var token_type: token.TokenType = switch (ch) {
                        '+' => .plus,
                        '-' => .minus,
                        '*' => .asterisk,
                        '/' => .slash,
                        '<' => .lt,
                        '>' => .gt,
                        ',' => .comma,
                        ';' => .semicolon,
                        '(' => .lparen,
                        ')' => .rparen,
                        '{' => .lbrace,
                        '}' => .rbrace,
                        else => .illegal,
                    };
                    if (ch == '=') {
                        if (l.peekChar() == '=') {
                            l.readChar();
                            token_type = .eq;
                        } else {
                            token_type = .assign;
                        }
                    } else if (ch == '!') {
                        if (l.peekChar() == '=') {
                            l.readChar();
                            token_type = .not_eq;
                        } else {
                            token_type = .bang;
                        }
                    }
                    try list.append(gpa, .{ .Type = token_type, .Literal = l.source[start..l.rdPosition] });
                    l.readChar();
                    continue :state .start;
                }
            },
            .int => {
                const start = l.atPosition;
                // while (l.ch) |chr| {
                //     if (!std.ascii.isDigit(chr)) break;
                //     l.readChar();
                // }
                while (l.ch != null and std.ascii.isDigit(l.ch.?)) {
                    l.readChar();
                }
                const str = l.source[start..l.atPosition];
                const num = try std.fmt.parseInt(i64, str, 10);
                try list.append(gpa, .{ .Type = .{ .int = num }, .Literal = str });
                continue :state .start;
            },
            .indentifer => {
                const start = l.atPosition;
                while (l.ch != null and (std.ascii.isDigit(l.ch.?) or
                    std.ascii.isAlphabetic(l.ch.?) or
                    l.ch.? == '_'))
                {
                    l.readChar();
                }

                const str = l.source[start..l.atPosition];
                const tokentype = l.lookIndent(str);
                try list.append(gpa, .{ .Type = tokentype, .Literal = str });
                continue :state .start;
            },
        }
        return list.toOwnedSlice(gpa);
    }

    pub fn readChar(l: *Lexer) void {
        l.atPosition = l.rdPosition;
        if (l.rdPosition >= l.source.len) {
            l.ch = null;
            return;
        } else {
            l.ch = l.source[l.rdPosition];
        }
        l.rdPosition += 1;
    }

    pub fn peekChar(l: *Lexer) u8 {
        if (l.rdPosition >= l.source.len) {
            return 0;
        }
        return l.source[l.rdPosition];
    }

    pub fn lookIndent(l: *Lexer, ident: []const u8) token.TokenType {
        _ = l;
        if (token.keywords.get(ident)) |token_type| {
            return token_type;
        }
        return .ident;
    }
};

test "nextToken_From go" {
    const gpa = std.testing.allocator;
    const input =
        \\let five = 5; 
        \\let ten = 10; 
        \\let add = fn(x, y) { 
        \\x + y; 
        \\}; 
        \\let result = add(five, ten); 
        \\!-/*5; 
        \\5 < 10 > 5; 
        \\if (5 < 10) { 
        \\return true; 
        \\} else { 
        \\return false; 
        \\} 
        \\10 == 10; 
        \\10 != 9;
    ;
    var l: Lexer = .init(input);
    const tokenList = try l.nextToken(gpa);
    defer gpa.free(tokenList);
    const Expected = struct {
        expected_type: std.meta.Tag(token.TokenType),
        expected_literal: []const u8,
    };

    const tests = [_]Expected{
        .{ .expected_type = .let, .expected_literal = "let" },
        .{ .expected_type = .ident, .expected_literal = "five" },
        .{ .expected_type = .assign, .expected_literal = "=" },
        .{ .expected_type = .int, .expected_literal = "5" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .let, .expected_literal = "let" },
        .{ .expected_type = .ident, .expected_literal = "ten" },
        .{ .expected_type = .assign, .expected_literal = "=" },
        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .let, .expected_literal = "let" },
        .{ .expected_type = .ident, .expected_literal = "add" },
        .{ .expected_type = .assign, .expected_literal = "=" },
        .{ .expected_type = .function, .expected_literal = "fn" },
        .{ .expected_type = .lparen, .expected_literal = "(" },
        .{ .expected_type = .ident, .expected_literal = "x" },
        .{ .expected_type = .comma, .expected_literal = "," },
        .{ .expected_type = .ident, .expected_literal = "y" },
        .{ .expected_type = .rparen, .expected_literal = ")" },
        .{ .expected_type = .lbrace, .expected_literal = "{" },
        .{ .expected_type = .ident, .expected_literal = "x" },
        .{ .expected_type = .plus, .expected_literal = "+" },
        .{ .expected_type = .ident, .expected_literal = "y" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .rbrace, .expected_literal = "}" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .let, .expected_literal = "let" },
        .{ .expected_type = .ident, .expected_literal = "result" },
        .{ .expected_type = .assign, .expected_literal = "=" },
        .{ .expected_type = .ident, .expected_literal = "add" },
        .{ .expected_type = .lparen, .expected_literal = "(" },
        .{ .expected_type = .ident, .expected_literal = "five" },
        .{ .expected_type = .comma, .expected_literal = "," },
        .{ .expected_type = .ident, .expected_literal = "ten" },
        .{ .expected_type = .rparen, .expected_literal = ")" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .bang, .expected_literal = "!" },
        .{ .expected_type = .minus, .expected_literal = "-" },
        .{ .expected_type = .slash, .expected_literal = "/" },
        .{ .expected_type = .asterisk, .expected_literal = "*" },
        .{ .expected_type = .int, .expected_literal = "5" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .int, .expected_literal = "5" },
        .{ .expected_type = .lt, .expected_literal = "<" },
        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .gt, .expected_literal = ">" },
        .{ .expected_type = .int, .expected_literal = "5" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },

        .{ .expected_type = .@"if", .expected_literal = "if" },
        .{ .expected_type = .lparen, .expected_literal = "(" },
        .{ .expected_type = .int, .expected_literal = "5" },
        .{ .expected_type = .lt, .expected_literal = "<" },
        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .rparen, .expected_literal = ")" },
        .{ .expected_type = .lbrace, .expected_literal = "{" },
        .{ .expected_type = .@"return", .expected_literal = "return" },
        .{ .expected_type = .true, .expected_literal = "true" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .rbrace, .expected_literal = "}" },
        .{ .expected_type = .@"else", .expected_literal = "else" },
        .{ .expected_type = .lbrace, .expected_literal = "{" },
        .{ .expected_type = .@"return", .expected_literal = "return" },
        .{ .expected_type = .false, .expected_literal = "false" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .rbrace, .expected_literal = "}" },

        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .eq, .expected_literal = "==" },
        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },
        .{ .expected_type = .int, .expected_literal = "10" },
        .{ .expected_type = .not_eq, .expected_literal = "!=" },
        .{ .expected_type = .int, .expected_literal = "9" },
        .{ .expected_type = .semicolon, .expected_literal = ";" },

        .{ .expected_type = .eof, .expected_literal = "" },
    };
    //
    for (tests, 0..) |expected, i| {
        const actual = tokenList[i];

        try std.testing.expectEqual(expected.expected_type, std.meta.activeTag(actual.Type));

        try std.testing.expectEqualStrings(expected.expected_literal, actual.Literal);
    }

    try std.testing.expectEqual(tests.len, tokenList.len);
}
