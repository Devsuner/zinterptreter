const std = @import("std");
const token = @import("./token.zig");
const ast = @import("./ast.zig");
const lexer = @import("./lexer.zig");

const Precedence = enum(u8) {
    lowest,
    equals, // ==
    lessgreater, // < >
    sum, // +  -
    porduct, // * /
    prefix, // -x or !x
    call, // fn(x)
};

fn tokenPrecedence(t: std.meta.Tag(token.TokenType)) Precedence {
    return switch (t) {
        .eq, .not_eq => .equals,
        .lt, .gt => .lessgreater,
        .plus, .minus => .sum,
        .slash, .asterisk => .porduct,
        .lparen => .call,
        else => .lowest,
    };
}

const Parser = struct {
    tokenList: []token.Token,
    pos: usize,
    errors: std.ArrayListUnmanaged([]const u8),
    error_arena: std.heap.ArenaAllocator,
    pub fn init(tokenList: []token.Token, child_allocator: std.mem.Allocator) Parser {
        var l: Parser = .{ .pos = 0, .tokenList = tokenList, .errors = .{}, .error_arena = std.heap.ArenaAllocator.init(child_allocator) };
        l.nextToken();
        return l;
    }

    pub fn deinit(self: *Parser) void {
        self.error_arena.deinit();
    }

    pub fn nextToken(self: *Parser) !void {
        if (self.pos < self.tokenList.len) {
            self.pos += 1;
        }
    }
    fn curToken(self: *Parser) token.Token {
        if (self.pos < self.tokenList.len) return self.tokenList[self.pos];
        return .{ .Type = .eof, .Literal = "" };
    }

    fn peekToken(self: *Parser) token.Token {
        if (self.pos + 1 < self.tokenList.len) return self.tokenList[self.pos + 1];
        return .{ .Type = .eof, .Literal = "" };
    }

    pub fn PareseProgram(p: *Parser, arena: std.mem.Allocator) !*ast.Program {
        const program = try arena.create(ast.Program);
        program.statements = .{};
        while (!p.curTokenIs(.eof)) {
            if (p.ParseStatement(arena)) |stmt| {
                try program.statements.append(arena, stmt);
            }
            p.nextToken();
        }
        return program;
    }

    pub fn ParseStatement(p: *Parser, arena: std.mem.Allocator) ?*ast.Statement {
        const tag = std.meta.activeTag(p.tokenList[p.atToken].Type);
        switch (tag) {
            .let => return p.parseLetStatement(arena),
            .@"return" => return p.parseReturnStatement(arena),
        }
    }

    pub fn parseLetStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.Statemnet {
        var stmt: *ast.LetStatemnet = arena.create(ast.LetStatemnet);
        stmt.token = self.curToken();
        if (!self.expectpeek(.ident)) return null;

        const name = arena.create(ast.Identifier) catch return null;
        name.token = self.curToken();
        name.value = switch (self.curToken().Type) {
            .ident => |n| n,
            else => self.curToken().Literal,
        };

        stmt.name = name;
        if (!self.expectpeek(.assign)) return null;
        self.nextToken();

        stmt.value = self.parseExpression(arena);
    }

    pub fn parseReturnStatement(p: *Parser, arena: std.mem.Allocator) ?*ast.Statement {}

    pub fn parseExpression(self: *Parser, arena: std.mem.Allocator, precedence: Precedence) ?*ast.Expression {
        var left_exp = self.paresePrefix(arena) orelse return null;
        while (!self.peekTokenIs(.semicolon) and @intFromEnum(precedence) < @intFromEnum(self.peekPrecedence())) {
            const peek_tag = std.meta.activeTag(self.peekToken().Type);
            const infix_exp = switch (peek_tag) {
                .plus, .minus, .slash, .asterisk, .eq, .not_eq, .lt, .gt => blk: {
                    self.nextToken();
                    break :blk self.paresePrefixExpression(arena, left_exp);
                },
                .lparen => blk: {
                    self.nextToken();
                    break :blk self.parseCallExpression(arena, left_exp);
                },
                else => null,
            };
        }
    }
    pub fn paresePrefix(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {}

    pub fn peekTokenIs(self: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        return (std.meta.activeTag(self.curToken().Type)) == t;
    }
    pub fn curTokenIs(self: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        return (std.meta.activeTag(self.curToken.Type)) == t;
    }
    pub fn expectpeek(p: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        if (p.peekTokenIs(t)) {
            p.nextToken();
            return true;
        } else return false;
    }
    fn peekPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(std.meta.activeTag(self.peekToken().Type));
    }
    fn curPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(std.meta.activeTag(self.curToken().Type));
    }
    pub fn parseInfixExpression(self: *Parser,arena: std.mem.Allocator,left: *ast.Expression)
};
