const std = @import("std");
pub const TokenType = union(enum(u8)) {
    illegal,
    eof,
    ident,
    int: i64, // 少一次转换

    // 运算符
    assign,
    plus,
    minus,
    bang,
    asterisk,
    slash,
    lt,
    gt,
    eq,
    not_eq,

    // 分隔符
    comma,
    semicolon,
    lparen,
    rparen,
    lbrace,
    rbrace,

    // 关键字
    function,
    let,
    true,
    false,
    @"if",
    @"else",
    @"return",
};

pub const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "fn", .function },
    .{ "let", .let },
    .{ "true", .true },
    .{ "false", .false },
    .{ "if", .@"if" },
    .{ "else", .@"else" },
    .{ "return", .@"return" },
});
pub const Token = struct {
    Type: TokenType,
    Literal: []const u8, // 原始切片，用于报错信息的打印
};
