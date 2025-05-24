const std = @import("std");

pub const Style = struct {
    color: ?[]const u8 = null,
    font_size: ?i32 = null,
    background: ?[]const u8 = null,
    pos_x: ?i32 = null,
    pos_y: ?i32 = null, 

    allocator: ?std.mem.Allocator = null,

    pub fn init(allocator: std.mem.Allocator) Style {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Style) void {
        if (self.allocator) |alloc| {
            if (self.color) |c| alloc.free(c);
            if (self.background) |b| alloc.free(b);
        }
        self.* = .{};
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Parser {
        return .{ .allocator = allocator, .content = content, .pos = 0 };
    }

    pub fn parse(self: *Parser) !Style {
        var style = Style.init(self.allocator);
        while (self.pos < self.content.len) {
            self.skipWhitespace();
            if (self.pos >= self.content.len) break;

            const key = try self.parseIdentifier();
            self.skipWhitespace();
            if (self.pos >= self.content.len or self.content[self.pos] != ':') {
                self.allocator.free(key);
                return error.InvalidFormat;
            }
            self.pos += 1; 
            self.skipWhitespace();

            const value = try self.parseValue();

            if (std.mem.eql(u8, key, "color")) {
                style.color = value;
            } else if (std.mem.eql(u8, key, "font-size")) {
                style.font_size = std.fmt.parseInt(i32, value, 10) catch |err| {
                    self.allocator.free(value);
                    self.allocator.free(key);
                    return err;
                };
                self.allocator.free(value); 
            } else if (std.mem.eql(u8, key, "background")) {
                style.background = value;
            } else if (std.mem.eql(u8, key, "pos_x")) {
                style.pos_x = std.fmt.parseInt(i32, value, 10) catch |err| {
                    self.allocator.free(value);
                    self.allocator.free(key);
                    return err;
                };
                self.allocator.free(value); 
            } else if (std.mem.eql(u8, key, "pos_y")) {
                style.pos_y = std.fmt.parseInt(i32, value, 10) catch |err| {
                    self.allocator.free(value);
                    self.allocator.free(key);
                    return err;
                };
                self.allocator.free(value); 
            } else {
                self.allocator.free(value);
            }

            self.allocator.free(key);
            self.skipWhitespace();
            if (self.pos < self.content.len and self.content[self.pos] == ';') {
                self.pos += 1; 
            } else if (self.pos < self.content.len) {
                self.skipWhitespace();
                if (self.pos < self.content.len) {
                    return error.InvalidFormat;
                }
            }
        }
        return style;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.content.len and std.ascii.isWhitespace(self.content[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseIdentifier(self: *Parser) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.content.len and (std.ascii.isAlphanumeric(self.content[self.pos]) or self.content[self.pos] == '-' or self.content[self.pos] == '_')) {
            self.pos += 1;
        }
        if (start == self.pos) return error.InvalidIdentifier;
        return try self.allocator.dupe(u8, self.content[start..self.pos]);
    }

    fn parseValue(self: *Parser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != ';' and !std.ascii.isWhitespace(self.content[self.pos])) {
            self.pos += 1;
        }
        if (start == self.pos) return error.InvalidValue;
        const value = try self.allocator.dupe(u8, std.mem.trim(u8, self.content[start..self.pos], " \n\t"));
        if (value.len == 0) {
            self.allocator.free(value);
            return error.InvalidValue;
        }
        return value;
    }
};
