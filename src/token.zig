const std = @import("std");
pub const TokenType = union(enum(u8)) {
    // 基础
    illegal,
    eof,
    ident: []const u8, // 存储变量名切片
    int: i64, // 存储 Lexer 预解析后的 64 位整数

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

    // 关键字 (使用 @"..." 避让 Zig 关键字)
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
    Type: TokenType, // 包含类型标记和解析后的值
    Literal: []const u8, // 原始切片，用于报错信息
};
