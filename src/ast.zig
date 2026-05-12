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
    pub fn string(self: *const Program) []const u8 {
        for (self.statements.items) |stmt| {
            const s = try stmt.string();
            return s;
        }
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
    let_statement: *LetStatemnet,
    return_statement: *ReturnStatement,
    expression: *ExpressionStatement,
    block: *BlockStatement,
    pub fn tokenLiteral(self: *Statement) []const u8 {
        return switch (self) {
            .let_statement => |ls| ls.token.Literal,
            // .return_statement => |rs| rs.
        };
    }

    pub fn string(self: *Statement, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .let => |s| s.string(allocator),
            .return_ => |s| s.string(allocator),
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
            .identifer => |i| i.token.Literal,
        };
    }
    pub fn string(self: *Expression, allocator: std.mem.Allocator) []const u8 {
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

pub const LetStatemnet = struct {
    token: token.Token,
    name: *Identifier,
    value: ?*Expression,
    pub fn tokenLiteral(self: *LetStatemnet) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *LetStatemnet, gpa: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        try buf.append(gpa, self.token.Literal);
        try buf.append(gpa, ' ');
        const ns = try self.name.string(gpa);
        defer gpa.free(ns);
        try buf.append(gpa, " = ");
        if (self.value) |stmt| {
            const vs = try stmt.string(gpa);
            defer gpa.free(vs);
            try buf.append(gpa, vs);
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
    pub fn string(self: *ReturnStatement) ![]const u8 {
        if (self.return_value) |item| {
            return item.tokenLiteral();
        }
    }
};
pub const ExpressionStatement = struct { token: token.Token, expression: ?*Expression };

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
    pub fn string(self: *Identifier, _: std.mem.Allocator) []const u8 {
        return self.value;
    }
};

pub const Boolean = struct {
    token: token.Token,
    value: bool,
    pub fn tokenLiteral(self: *ReturnStatement) []const u8 {
        return self.token.Literal;
    }
    pub fn string(
        self: *Boolean,
        _: std.mem.Allocator,
    ) ![]const u8 {
        return self.token.Literal;
    }
};

pub const IntegerLiteral = struct {
    token: token.Token,
    pub fn tokenLiteral(self: *IntegerLiteral) []const u8 {
        return self.token.Literal;
    }
    pub fn string(self: *IntegerLiteral) ![]const u8 {
        return self.token.Literal;
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
    token: token.Token, // 操作符 token，如 '+'
    left: ?*Expression,
    operator: []const u8,
    right: ?*Expression,

    pub fn tokenLiteral(self: *InfixExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: InfixExpression, allocator: std.mem.Allocator) ![]const u8 {
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
        try buf.toOwnedSlice(allocator);
    }
};

pub const CallExpression = struct {
    token: token.Token,
    function: ?*Expression,
    arguments: std.ArrayListUnmanaged(*Expression),

    pub fn tokenLiteral(self: CallExpression) []const u8 {
        return self.token.Literal;
    }

    pub fn string(self: *CallExpression, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).empty;
        if (self.function) |f| {
            const fs = try f.string(allocator);
            defer allocator.free(fs);
            try buf.appendSlice(allocator, fs);
        }
        try buf.append('(');
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
