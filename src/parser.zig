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

pub const Parser = struct {
    tokenList: []token.Token,
    pos: usize,
    errors: std.ArrayListUnmanaged([]const u8),
    error_arena: std.heap.ArenaAllocator,
    pub fn init(tokenList: []token.Token, child_allocator: std.mem.Allocator) Parser {
        const l: Parser = .{ .pos = 0, .tokenList = tokenList, .errors = .empty, .error_arena = std.heap.ArenaAllocator.init(child_allocator) };
        return l;
    }

    pub fn deinit(self: *Parser) void {
        self.error_arena.deinit();
    }

    pub fn nextToken(self: *Parser) void {
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

    pub fn parseProgram(p: *Parser, arena: std.mem.Allocator) !*ast.Program {
        const program = try arena.create(ast.Program);
        program.statements = .empty;
        while (!p.curTokenIs(.eof)) {
            if (p.parseStatement(arena)) |stmt| {
                try program.statements.append(arena, stmt);
            }
            p.nextToken();
        }
        return program;
    }

    pub fn parseStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.Statement {
        const tag = std.meta.activeTag(self.curToken().Type);
        switch (tag) {
            .let => return self.parseLetStatement(arena),
            .@"return" => return self.parseReturnStatement(arena),
            else => return self.parseExpressionStatement(arena),
        }
    }

    pub fn parseExpressionStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.Statement {
        const stmt = arena.create(ast.ExpressionStatement) catch return null;

        stmt.token = self.curToken();
        stmt.expression = self.parseExpression(arena, .lowest);

        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        const result = arena.create(ast.Statement) catch return null;
        result.* = .{ .expression = stmt };
        return result;
    }

    pub fn parseLetStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.Statement {
        var stmt: *ast.LetStatement = arena.create(ast.LetStatement) catch return null;
        stmt.token = self.curToken();
        if (!self.expectpeek(.ident)) return null;

        const name = arena.create(ast.Identifier) catch return null;
        name.token = self.curToken();
        name.value = self.curToken().Literal;

        stmt.name = name;
        if (!self.expectpeek(.assign)) return null;
        self.nextToken();

        stmt.value = self.parseExpression(arena, .lowest);

        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        const exp = arena.create(ast.Statement) catch return null;
        exp.* = .{ .let_statement = stmt };
        return exp;
    }

    pub fn parseReturnStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.Statement {
        const stmt = arena.create(ast.ReturnStatement) catch return null;
        stmt.token = self.curToken();
        self.nextToken();

        stmt.return_value = self.parseExpression(arena, .lowest);

        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        const exp = arena.create(ast.Statement) catch return null;
        exp.* = .{ .return_statement = stmt };
        return exp;
    }

    pub fn parseBlockStatement(self: *Parser, arena: std.mem.Allocator) ?*ast.BlockStatement {
        const block = arena.create(ast.BlockStatement) catch return null;

        block.token = self.curToken();
        block.statements = .empty;

        self.nextToken();

        while (!self.curTokenIs(.rbrace) and !self.curTokenIs(.eof)) {
            if (self.parseStatement(arena)) |stmt| {
                block.statements.append(arena, stmt) catch {};
            }
            self.nextToken();
        }

        return block;
    }

    pub fn parseExpression(self: *Parser, arena: std.mem.Allocator, precedence: Precedence) ?*ast.Expression {
        var left_exp = self.parsePrefix(arena) orelse return null;
        while (!self.peekTokenIs(.semicolon) and @intFromEnum(precedence) < @intFromEnum(self.peekPrecedence())) {
            const peek_tag = std.meta.activeTag(self.peekToken().Type);
            const infix_exp = switch (peek_tag) {
                .plus, .minus, .slash, .asterisk, .eq, .not_eq, .lt, .gt => blk: {
                    self.nextToken();
                    break :blk self.parseInfixExpression(arena, left_exp);
                },
                .lparen => blk: {
                    self.nextToken();
                    break :blk self.parseCallExpression(arena, left_exp);
                },
                else => null,
            };
            if (infix_exp) |exp| {
                left_exp = exp;
            } else return left_exp;
        }
        return left_exp;
    }
    pub fn parsePrefix(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const tag = std.meta.activeTag(self.curToken().Type);
        switch (tag) {
            .ident => return self.parseIdentifier(arena),
            .int => return self.parseIntegerLiteral(arena),
            .bang, .minus => return self.parsePrefixExpression(arena),
            .true, .false => return self.parseBoolean(arena),
            .lparen => return self.parseGroupedExpression(arena),
            .@"if" => return self.parseIfExpression(arena),
            .function => return self.parseFunctionLiteral(arena),
            else => {
                self.noPrefixParseFnError(self.curToken().Type);
                return null;
            },
        }
    }
    pub fn parseFunctionLiteral(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const lit = arena.create(ast.FunctionLiteral) catch return null;
        lit.token = self.curToken();

        if (!self.expectpeek(.lparen)) return null;

        lit.parameters = self.parseFunctionParameters(arena) orelse return null;

        if (!self.expectpeek(.lbrace)) return null;

        lit.body = self.parseBlockStatement(arena);

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .function = lit };

        return exp;
    }

    fn parseFunctionParameters(self: *Parser, arena: std.mem.Allocator) ?std.ArrayListUnmanaged(*ast.Identifier) {
        var params: std.ArrayListUnmanaged(*ast.Identifier) = .empty;

        if (self.peekTokenIs(.rparen)) {
            self.nextToken();
            return params;
        }

        self.nextToken();

        {
            const ident = arena.create(ast.Identifier) catch return null;
            ident.token = self.curToken();
            ident.value = self.curToken().Literal;
            params.append(arena, ident) catch return null;
        }

        while (self.peekTokenIs(.comma)) {
            self.nextToken();
            self.nextToken();

            const ident = arena.create(ast.Identifier) catch return null;
            ident.token = self.curToken();
            ident.value = self.curToken().Literal;
            params.append(arena, ident) catch return null;
        }

        if (!self.expectpeek(.rparen)) return null;

        return params;
    }

    pub fn parseIfExpression(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const expr = arena.create(ast.IfExpression) catch return null;
        expr.token = self.curToken();
        expr.condition = null;
        expr.consequence = null;
        expr.alternative = null;

        if (!self.expectpeek(.lparen)) return null;

        self.nextToken();
        expr.condition = self.parseExpression(arena, .lowest);

        if (!self.expectpeek(.rparen)) return null;
        if (!self.expectpeek(.lbrace)) return null;

        expr.consequence = self.parseBlockStatement(arena);

        if (self.peekTokenIs(.@"else")) {
            self.nextToken();
            if (!self.expectpeek(.lbrace)) return null;

            expr.alternative = self.parseBlockStatement(arena);
        }
        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .if_expr = expr };
        return exp;
    }

    pub fn parseGroupedExpression(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        self.nextToken();
        const exp = self.parseExpression(arena, .lowest);
        if (!self.expectpeek(.rparen)) {
            return null;
        }
        return exp;
    }

    pub fn parseBoolean(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const bol = arena.create(ast.Boolean) catch return null;
        bol.token = self.curToken();
        bol.value = self.curTokenIs(.true);

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .boolean = bol };
        return exp;
    }

    pub fn parsePrefixExpression(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const expr = arena.create(ast.PrefixExpression) catch return null;
        expr.token = self.curToken();
        expr.operator = self.curToken().Literal;

        self.nextToken();
        expr.right = self.parseExpression(arena, .prefix);

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .prefix = expr };
        return exp;
    }

    pub fn parseInfixExpression(self: *Parser, arena: std.mem.Allocator, left: *ast.Expression) ?*ast.Expression {
        const expr = arena.create(ast.InfixExpression) catch return null;
        expr.token = self.curToken();
        expr.operator = self.curToken().Literal;
        expr.left = left;

        const prec = self.curPrecedence();
        self.nextToken();
        expr.right = self.parseExpression(arena, prec);

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .infix = expr };
        return exp;
    }

    pub fn parseCallExpression(self: *Parser, arena: std.mem.Allocator, function: *ast.Expression) ?*ast.Expression {
        const expr = arena.create(ast.CallExpression) catch return null;
        expr.token = self.curToken();
        expr.function = function;
        expr.arguments = .empty;

        if (self.peekTokenIs(.rparen)) {
            self.nextToken();
        } else {
            self.nextToken();
            while (true) {
                if (self.parseExpression(arena, .lowest)) |arg| {
                    expr.arguments.append(arena, arg) catch return null;
                }
                if (!self.peekTokenIs(.comma)) break;
                self.nextToken();
                self.nextToken();
            }
            if (!self.expectpeek(.rparen)) return null;
        }

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .call = expr };
        return exp;
    }

    pub fn parseIdentifier(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const ident = arena.create(ast.Identifier) catch return null;
        ident.token = self.curToken();
        ident.value = self.curToken().Literal;

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .identifier = ident };
        return exp;
    }

    pub fn parseIntegerLiteral(self: *Parser, arena: std.mem.Allocator) ?*ast.Expression {
        const lit = arena.create(ast.IntegerLiteral) catch return null;
        lit.token = self.curToken();
        lit.value = switch (self.curToken().Type) {
            .int => |v| v,
            else => 0,
        };

        const exp = arena.create(ast.Expression) catch return null;
        exp.* = .{ .integer = lit };
        return exp;
    }

    pub fn peekTokenIs(self: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        return (std.meta.activeTag(self.peekToken().Type)) == t;
    }
    pub fn curTokenIs(self: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        return (std.meta.activeTag(self.curToken().Type)) == t;
    }
    pub fn expectpeek(self: *Parser, t: std.meta.Tag(token.TokenType)) bool {
        if (self.peekTokenIs(t)) {
            self.nextToken();
            return true;
        } else {
            self.peekError(t);
            return false;
        }
    }
    fn peekPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(std.meta.activeTag(self.peekToken().Type));
    }
    fn curPrecedence(self: *Parser) Precedence {
        return tokenPrecedence(std.meta.activeTag(self.curToken().Type));
    }

    fn peekError(self: *Parser, t: std.meta.Tag(token.TokenType)) void {
        const msg = std.fmt.allocPrint(self.error_arena.child_allocator, "expected next token to be {s}, got {s} instead", .{ @tagName(t), @tagName((std.meta.activeTag(self.peekToken().Type))) }) catch "error formatting error";
        self.errors.append(self.error_arena.allocator(), msg) catch {};
    }

    fn noPrefixParseFnError(self: *Parser, t: token.TokenType) void {
        const msg = std.fmt.allocPrint(
            self.error_arena.allocator(),
            "no prefix parse function for {s} found",
            .{@tagName(std.meta.activeTag(t))},
        ) catch "error formatting error";
        self.errors.append(self.error_arena.allocator(), msg) catch {};
    }
};

test "let statements" {
    const allocator = std.testing.allocator;

    const tests = [_]struct { input: []const u8, expected_ident: []const u8, expected_value: []const u8 }{
        .{ .input = "let x = 5;", .expected_ident = "x", .expected_value = "5" },
        .{ .input = "let y = true;", .expected_ident = "y", .expected_value = "true" },
        .{ .input = "let foobar = y;", .expected_ident = "foobar", .expected_value = "y" },
    };

    for (tests) |tt| {
        var my_lexer = lexer.Lexer.init(tt.input);
        const tokens = try my_lexer.nextToken(allocator);
        defer allocator.free(tokens);

        var parser = Parser.init(tokens, allocator);
        defer parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(allocator);
        defer ast_arena.deinit();

        const program = try parser.parseProgram(ast_arena.allocator());

        try std.testing.expectEqual(0, parser.errors.items.len);
        try std.testing.expectEqual(1, program.statements.items.len);

        const stmt = program.statements.items[0].*;
        try std.testing.expectEqualStrings("let", stmt.tokenLiteral());

        try std.testing.expect(stmt == .let_statement);
        try std.testing.expectEqualStrings(tt.expected_ident, stmt.let_statement.name.value);
        try std.testing.expectEqualStrings(tt.expected_ident, stmt.let_statement.name.tokenLiteral());
    }
}

test "return statements" {
    const allocator = std.testing.allocator;

    const tests = [_]struct { input: []const u8, expected_value: []const u8 }{
        .{ .input = "return 5;", .expected_value = "5" },
        .{ .input = "return true;", .expected_value = "true" },
        .{ .input = "return foobar;", .expected_value = "foobar" },
    };

    for (tests) |tt| {
        var my_lexer = lexer.Lexer.init(tt.input);
        const tokens = try my_lexer.nextToken(allocator);
        defer allocator.free(tokens);

        var parser = Parser.init(tokens, allocator);
        defer parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(allocator);
        defer ast_arena.deinit();

        const program = try parser.parseProgram(ast_arena.allocator());

        try std.testing.expectEqual(0, parser.errors.items.len);
        try std.testing.expectEqual(1, program.statements.items.len);

        const stmt = program.statements.items[0].*;
        try std.testing.expect(stmt == .return_statement);
        try std.testing.expectEqualStrings("return", stmt.tokenLiteral());

        if (stmt.return_statement.return_value) |val| {
            try std.testing.expectEqualStrings(tt.expected_value, val.tokenLiteral());
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "identifier expression" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("foobar;");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    try std.testing.expect(stmt == .expression);

    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .identifier);
    try std.testing.expectEqualStrings("foobar", exp.identifier.value);
    try std.testing.expectEqualStrings("foobar", exp.tokenLiteral());
}

test "integer literal expression" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("5;");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    try std.testing.expect(stmt == .expression);

    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .integer);

    try std.testing.expectEqual(5, exp.integer.value);
    try std.testing.expectEqualStrings("5", exp.tokenLiteral());
}

test "prefix expressions" {
    const allocator = std.testing.allocator;

    const tests = [_]struct { input: []const u8, operator: []const u8, value: []const u8 }{
        .{ .input = "!5;", .operator = "!", .value = "5" },
        .{ .input = "-15;", .operator = "-", .value = "15" },
        .{ .input = "!foobar;", .operator = "!", .value = "foobar" },
        .{ .input = "-foobar;", .operator = "-", .value = "foobar" },
        .{ .input = "!true;", .operator = "!", .value = "true" },
        .{ .input = "!false;", .operator = "!", .value = "false" },
    };

    for (tests) |tt| {
        var my_lexer = lexer.Lexer.init(tt.input);
        const tokens = try my_lexer.nextToken(allocator);
        defer allocator.free(tokens);

        var parser = Parser.init(tokens, allocator);
        defer parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(allocator);
        defer ast_arena.deinit();

        const program = try parser.parseProgram(ast_arena.allocator());

        try std.testing.expectEqual(0, parser.errors.items.len);
        try std.testing.expectEqual(1, program.statements.items.len);

        const stmt = program.statements.items[0].*;
        try std.testing.expect(stmt == .expression);

        const exp = stmt.expression.expression.?;
        try std.testing.expect(exp.* == .prefix);

        try std.testing.expectEqualStrings(tt.operator, exp.prefix.operator);
        if (exp.prefix.right) |right| {
            try std.testing.expectEqualStrings(tt.value, right.tokenLiteral());
        } else {
            return error.TestUnexpectedResult;
        }
    }
}

test "infix expressions" {
    const allocator = std.testing.allocator;

    const tests = [_]struct { input: []const u8, left: []const u8, operator: []const u8, right: []const u8 }{
        .{ .input = "5 + 5;", .left = "5", .operator = "+", .right = "5" },
        .{ .input = "5 - 5;", .left = "5", .operator = "-", .right = "5" },
        .{ .input = "5 * 5;", .left = "5", .operator = "*", .right = "5" },
        .{ .input = "5 / 5;", .left = "5", .operator = "/", .right = "5" },
        .{ .input = "5 > 5;", .left = "5", .operator = ">", .right = "5" },
        .{ .input = "5 < 5;", .left = "5", .operator = "<", .right = "5" },
        .{ .input = "5 == 5;", .left = "5", .operator = "==", .right = "5" },
        .{ .input = "5 != 5;", .left = "5", .operator = "!=", .right = "5" },
        .{ .input = "foobar + barfoo;", .left = "foobar", .operator = "+", .right = "barfoo" },
        .{ .input = "true == true", .left = "true", .operator = "==", .right = "true" },
        .{ .input = "true != false", .left = "true", .operator = "!=", .right = "false" },
        .{ .input = "false == false", .left = "false", .operator = "==", .right = "false" },
    };

    for (tests) |tt| {
        var my_lexer = lexer.Lexer.init(tt.input);
        const tokens = try my_lexer.nextToken(allocator);
        defer allocator.free(tokens);

        var parser = Parser.init(tokens, allocator);
        defer parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(allocator);
        defer ast_arena.deinit();

        const program = try parser.parseProgram(ast_arena.allocator());

        try std.testing.expectEqual(0, parser.errors.items.len);
        try std.testing.expectEqual(1, program.statements.items.len);

        const stmt = program.statements.items[0].*;
        try std.testing.expect(stmt == .expression);

        const exp = stmt.expression.expression.?;
        try std.testing.expect(exp.* == .infix);

        try std.testing.expectEqualStrings(tt.operator, exp.infix.operator);
        if (exp.infix.left) |left| {
            try std.testing.expectEqualStrings(tt.left, left.tokenLiteral());
        } else return error.TestUnexpectedResult;
        if (exp.infix.right) |right| {
            try std.testing.expectEqualStrings(tt.right, right.tokenLiteral());
        } else return error.TestUnexpectedResult;
    }
}

test "operator precedence" {
    const allocator = std.testing.allocator;

    const tests = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "-a * b", .expected = "((-a) * b)" },
        .{ .input = "!-a", .expected = "(!(-a))" },
        .{ .input = "a + b + c", .expected = "((a + b) + c)" },
        .{ .input = "a + b - c", .expected = "((a + b) - c)" },
        .{ .input = "a * b * c", .expected = "((a * b) * c)" },
        .{ .input = "a * b / c", .expected = "((a * b) / c)" },
        .{ .input = "a + b / c", .expected = "(a + (b / c))" },
        .{ .input = "a + b * c + d / e - f", .expected = "(((a + (b * c)) + (d / e)) - f)" },
        .{ .input = "3 + 4; -5 * 5", .expected = "(3 + 4)((-5) * 5)" },
        .{ .input = "5 > 4 == 3 < 4", .expected = "((5 > 4) == (3 < 4))" },
        .{ .input = "5 < 4 != 3 > 4", .expected = "((5 < 4) != (3 > 4))" },
        .{ .input = "3 + 4 * 5 == 3 * 1 + 4 * 5", .expected = "((3 + (4 * 5)) == ((3 * 1) + (4 * 5)))" },
        .{ .input = "true", .expected = "true" },
        .{ .input = "false", .expected = "false" },
        .{ .input = "3 > 5 == false", .expected = "((3 > 5) == false)" },
        .{ .input = "3 < 5 == true", .expected = "((3 < 5) == true)" },
        .{ .input = "1 + (2 + 3) + 4", .expected = "((1 + (2 + 3)) + 4)" },
        .{ .input = "(5 + 5) * 2", .expected = "((5 + 5) * 2)" },
        .{ .input = "2 / (5 + 5)", .expected = "(2 / (5 + 5))" },
        .{ .input = "-(5 + 5)", .expected = "(-(5 + 5))" },
        .{ .input = "!(true == true)", .expected = "(!(true == true))" },
        .{ .input = "a + add(b * c) + d", .expected = "((a + add((b * c))) + d)" },
        .{
            .input = "add(a, b, 1, 2 * 3, 4 + 5, add(6, 7 * 8))",
            .expected = "add(a, b, 1, (2 * 3), (4 + 5), add(6, (7 * 8)))",
        },
        .{ .input = "add(a + b + c * d / f + g)", .expected = "add((((a + b) + ((c * d) / f)) + g))" },
        // 带分号的
        .{
            .input = "a + b * c + d / e - f;",
            .expected = "(((a + (b * c)) + (d / e)) - f)",
        },
    };

    for (tests) |tt| {
        var my_lexer = lexer.Lexer.init(tt.input);
        const tokens = try my_lexer.nextToken(allocator);
        defer allocator.free(tokens);

        var parser = Parser.init(tokens, allocator);
        defer parser.deinit();

        var ast_arena = std.heap.ArenaAllocator.init(allocator);
        defer ast_arena.deinit();

        const program = try parser.parseProgram(ast_arena.allocator());

        // 一直走, 就算有错误, 设计之初就是要一次性扫出全部的错误
        const result = try program.string(allocator);
        defer allocator.free(result);

        try std.testing.expectEqualStrings(tt.expected, result);
    }
}

test "if expression" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("if (x < y) { x }");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    try std.testing.expect(stmt == .expression);

    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .if_expr);

    //test condition
    const cond = exp.if_expr.condition.?;
    try std.testing.expect(cond.* == .infix);
    try std.testing.expectEqualStrings("<", cond.infix.operator);

    // test consequence
    try std.testing.expect(exp.if_expr.consequence != null);
    try std.testing.expectEqual(1, exp.if_expr.consequence.?.statements.items.len);

    // test alternative
    try std.testing.expect(exp.if_expr.alternative == null);
}

test "if-else expression" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("if (x < y) { x } else { y }");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .if_expr);

    // 验证 alternative 存在
    try std.testing.expect(exp.if_expr.alternative != null);
    try std.testing.expectEqual(1, exp.if_expr.alternative.?.statements.items.len);
}

test "function literal" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("fn(x, y) { x + y; }");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    try std.testing.expect(stmt == .expression);

    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .function);

    try std.testing.expectEqual(2, exp.function.parameters.items.len);
    try std.testing.expectEqualStrings("x", exp.function.parameters.items[0].value);
    try std.testing.expectEqualStrings("y", exp.function.parameters.items[1].value);

    try std.testing.expect(exp.function.body != null);
    try std.testing.expectEqual(1, exp.function.body.?.statements.items.len);
}

test "call expression" {
    const allocator = std.testing.allocator;

    var my_lexer = lexer.Lexer.init("add(1, 2 * 3, 4 + 5);");
    const tokens = try my_lexer.nextToken(allocator);
    defer allocator.free(tokens);

    var parser = Parser.init(tokens, allocator);
    defer parser.deinit();

    var ast_arena = std.heap.ArenaAllocator.init(allocator);
    defer ast_arena.deinit();

    const program = try parser.parseProgram(ast_arena.allocator());

    try std.testing.expectEqual(0, parser.errors.items.len);
    try std.testing.expectEqual(1, program.statements.items.len);

    const stmt = program.statements.items[0].*;
    const exp = stmt.expression.expression.?;
    try std.testing.expect(exp.* == .call);

    // test parsefuncitonname
    try std.testing.expect(exp.call.function.?.* == .identifier);
    try std.testing.expectEqualStrings("add", exp.call.function.?.identifier.value);

    // test parmam
    try std.testing.expectEqual(3, exp.call.arguments.items.len);
    try std.testing.expect(exp.call.arguments.items[0].* == .integer);
    try std.testing.expectEqual(1, exp.call.arguments.items[0].integer.value);

    //(2 * 3)
    try std.testing.expect(exp.call.arguments.items[1].* == .infix);

    //(4 + 5)
    try std.testing.expect(exp.call.arguments.items[2].* == .infix);
}
