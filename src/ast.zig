const std = @import("std");
const token = @import("./token.zig");

pub const Program = struct {
    statements: std.ArrayList(*Statement),
    pub fn tokenLiteral(self: Program) []const u8 {
        if (self.statements.items.len > 0) {
            return self.statements.items[0].tokenLiteral();
        } else {
            return "";
        }
    }
    pub fn string(self: *const Program, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        for (self.statements.items) |stmt| {
            const s = try stmt.string(allocator);
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        }
        return buf.toOwnedSlice(allocator);
    }
};
// pub const Node = union(enum) {
//     program: *Program,
//     statement: Statement,
//     expression: Expression,
//     const Self = @This();
//     pub fn tokenLiteral(self: Self) []const u8 {
//
//         return switch (self) {
//             .program => |i| i.tokenLiteral(),
//             .statement => |i| i.tokenLiteral(),
//             .expression => |i| i.tokenLiteral(),
//         };
//     }
// };

pub const Statement = union(enum) {
    let_statement: *LetStatement,
    return_statement: *ReturnStatement,
    expression: *ExpressionStatement,
    block: *BlockStatement,
    pub fn tokenLiteral(self: *const Statement) []const u8 {
        return switch (self.*) {
            .let_statement => |ls| ls.token.Literal,
            .return_statement => |rs| rs.token.Literal,
            .expression => |es| es.tokenLiteral(),
            .block => |bs| bs.token.Literal,
        };
    }

    pub fn string(self: *Statement, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        return switch (self.*) {
            .let_statement => |s| s.string(allocator),
            .return_statement => |s| s.string(allocator),
            .expression => |s| s.string(allocator),
            .block => |s| s.string(allocator),
        };
    }
};

pub const Expression = union(enum) {
    identifier: *Identifier,
    boolean: *Boolean,
    integer: *IntegerLiteral,
    prefix: *PrefixExpression,
    infix: *InfixExpression,
    if_expr: *IfExpression,
    function: *FunctionLiteral,
    call: *CallExpression,
    pub fn tokenLiteral(self: *Expression) []const u8 {
        return switch (self.*) {
            .identifier => |i| i.token.Literal,
            .boolean => |b| b.token.Literal,
            .integer => |il| il.token.Literal,
            .prefix => |pe| pe.token.Literal,
            .infix => |ie| ie.token.Literal,
            .if_expr => |ie| ie.token.Literal,
            .function => |fl| fl.token.Literal,
            .call => |ce| ce.token.Literal,
        };
    }
    pub fn string(self: *Expression, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        return switch (self.*) {
            .identifier => |e| e.string(allocator),
            .boolean => |e| e.string(allocator),
            .integer => |e| e.string(allocator),
            .prefix => |e| e.string(allocator),
            .infix => |e| e.string(allocator),
            .if_expr => |e| e.string(allocator),
            .function => |e| e.string(allocator),
            .call => |e| e.string(allocator),
        };
    }
};

pub const LetStatement = struct {
    token: token.Token,
    name: *Identifier,
    value: ?*Expression,
    pub fn tokenLiteral(self: *LetStatement) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *LetStatement, gpa: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(gpa, self.token.Literal);
        try buf.append(gpa, ' ');
        const ns = try self.name.string(gpa);
        defer gpa.free(ns);
        try buf.appendSlice(gpa, ns);
        try buf.appendSlice(gpa, " = ");
        if (self.value) |stmt| {
            const vs = try stmt.string(gpa);
            defer gpa.free(vs);
            try buf.appendSlice(gpa, vs);
        }
        try buf.append(gpa, ';');
        return buf.toOwnedSlice(gpa);
    }
};

pub const ReturnStatement = struct {
    token: token.Token,
    return_value: ?*Expression,
    pub fn tokenLiteral(self: *ReturnStatement) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *ReturnStatement, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(allocator, self.token.Literal);
        try buf.append(allocator, ' ');
        if (self.return_value) |item| {
            const vs = try item.string(allocator);
            defer allocator.free(vs);
            try buf.appendSlice(allocator, vs);
        }
        try buf.append(allocator, ';');
        return buf.toOwnedSlice(allocator);
    }
};
pub const ExpressionStatement = struct {
    token: token.Token,
    expression: ?*Expression,

    pub fn tokenLiteral(self: *ExpressionStatement) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *ExpressionStatement, allocator: std.mem.Allocator) ![]const u8 {
        if (self.expression) |exp| {
            return exp.string(allocator);
        }
        return "";
    }
};

pub const BlockStatement = struct {
    token: token.Token,
    statements: std.ArrayList(*Statement),

    pub fn tokenLiteral(self: *BlockStatement) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *BlockStatement, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        for (self.statements.items) |value| {
            const s = try value.string(allocator);
            defer allocator.free(s);
            try buf.appendSlice(allocator, s);
        }
        return buf.toOwnedSlice(allocator);
    }
};
pub const Identifier = struct {
    token: token.Token,
    value: []const u8,
    pub fn tokenLiteral(self: *Identifier) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *Identifier, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, self.value);
    }
};

pub const Boolean = struct {
    token: token.Token,
    value: bool,
    pub fn tokenLiteral(self: *Boolean) []const u8 {
        return self.token.Literal;
    }
    pub fn string(
        self: *Boolean,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        return allocator.dupe(u8, self.token.Literal);
    }
};

pub const IntegerLiteral = struct {
    token: token.Token,
    value: i64,
    pub fn tokenLiteral(self: *IntegerLiteral) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *IntegerLiteral, allocator: std.mem.Allocator) ![]const u8 {
        return allocator.dupe(u8, self.token.Literal);
    }
};

pub const PrefixExpression = struct {
    token: token.Token, // 前缀操作符 token
    operator: []const u8,
    right: ?*Expression,

    pub fn tokenLiteral(self: *PrefixExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *PrefixExpression, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.append(allocator, '(');
        try buf.appendSlice(allocator, self.operator);
        if (self.right) |r| {
            const rs = try r.string(allocator);
            defer allocator.free(rs);
            try buf.appendSlice(allocator, rs);
        }
        try buf.append(allocator, ')');
        return buf.toOwnedSlice(allocator);
    }
};

pub const InfixExpression = struct {
    token: token.Token, // 操作符 token，'+'
    left: ?*Expression,
    operator: []const u8,
    right: ?*Expression,

    pub fn tokenLiteral(self: *InfixExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *InfixExpression, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.append(allocator, '(');
        if (self.left) |l| {
            const ls = try l.string(allocator);
            defer allocator.free(ls);
            try buf.appendSlice(allocator, ls);
        }
        try buf.append(allocator, ' ');
        try buf.appendSlice(allocator, self.operator);
        try buf.append(allocator, ' ');
        if (self.right) |r| {
            const rs = try r.string(allocator);
            defer allocator.free(rs);
            try buf.appendSlice(allocator, rs);
        }
        try buf.append(allocator, ')');
        return buf.toOwnedSlice(allocator);
    }
};

pub const IfExpression = struct {
    token: token.Token,
    condition: ?*Expression,
    consequence: ?*BlockStatement,
    alternative: ?*BlockStatement,

    pub fn tokenLiteral(self: *IfExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *IfExpression, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(allocator, "if");
        if (self.condition) |cond| {
            const cs = try cond.string(allocator);
            defer allocator.free(cs);
            try buf.append(allocator, ' ');
            try buf.appendSlice(allocator, cs);
        }
        try buf.append(allocator, ' ');
        if (self.consequence) |cons| {
            const cs = try cons.string(allocator);
            defer allocator.free(cs);
            try buf.appendSlice(allocator, cs);
        }
        if (self.alternative) |alt| {
            try buf.appendSlice(allocator, "else ");
            const as = try alt.string(allocator);
            defer allocator.free(as);
            try buf.appendSlice(allocator, as);
        }
        return buf.toOwnedSlice(allocator);
    }
};

pub const FunctionLiteral = struct {
    token: token.Token,
    parameters: std.ArrayListUnmanaged(*Identifier),
    body: ?*BlockStatement,

    pub fn tokenLiteral(self: *FunctionLiteral) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *FunctionLiteral, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).empty;
        try buf.appendSlice(allocator, self.token.Literal);
        try buf.append(allocator, '(');
        for (self.parameters.items, 0..) |parm, i| {
            if (i > 0) try buf.appendSlice(allocator, ", ");
            const ps = try parm.string(allocator);
            defer allocator.free(ps);
            try buf.appendSlice(allocator, ps);
        }
        try buf.appendSlice(allocator, ") ");
        if (self.body) |b| {
            const bs = try b.string(allocator);
            defer allocator.free(bs);
            try buf.appendSlice(allocator, bs);
        }
        return try buf.toOwnedSlice(allocator);
    }
};

pub const CallExpression = struct {
    token: token.Token,
    function: ?*Expression,
    arguments: std.ArrayListUnmanaged(*Expression),

    pub fn tokenLiteral(self: *CallExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *CallExpression, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).empty;
        if (self.function) |f| {
            const fs = try f.string(allocator);
            defer allocator.free(fs);
            try buf.appendSlice(allocator, fs);
        }
        try buf.append(allocator, '(');
        for (self.arguments.items, 0..) |arg, i| {
            if (i > 0) try buf.appendSlice(allocator, ", ");
            const arg_str = try arg.string(allocator);
            defer allocator.free(arg_str);
            try buf.appendSlice(allocator, arg_str);
        }
        try buf.append(allocator, ')');
        return buf.toOwnedSlice(allocator);
    }
};
