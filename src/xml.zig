const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

pub const NodeType = enum {
    Element,
    Text,
    Comment,
    Document,
};

fn log(comptime text: []const u8, args: anytype) void {
    std.debug.print("[XML] "++text, args);
}

pub const Node = struct {
    node_type: NodeType,
    name: ?[]const u8,
    attributes: StringHashMap([]const u8),
    children: ArrayList(*Node),
    text: ?[]const u8,
    allocator: Allocator,
    parent: ?*Node,

    pub fn init(allocator: Allocator, node_type: NodeType, name: ?[]const u8, text: ?[]const u8) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{
            .node_type = node_type,
            .name = if (name) |n| try allocator.dupe(u8, n) else null,
            .attributes = StringHashMap([]const u8).init(allocator),
            .children = ArrayList(*Node).init(allocator),
            .text = if (text) |t| try allocator.dupe(u8, t) else null,
            .allocator = allocator,
            .parent = null,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        if (self.name) |n| self.allocator.free(n);
        if (self.text) |t| self.allocator.free(t);
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.attributes.deinit();
        for (self.children.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn appendChild(self: *Node, child: *Node) !void {
        child.parent = self;
        try self.children.append(child);
    }

    pub fn prependChild(self: *Node, child: *Node) !void {
        child.parent = self;
        try self.children.insert(0, child);
    }

    pub fn insertChildAt(self: *Node, index: usize, child: *Node) !void {
        child.parent = self;
        try self.children.insert(index, child);
    }

    pub fn removeChild(self: *Node, child: *Node) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                child.parent = null;
                _ = self.children.orderedRemove(i);
                return;
            }
        }
    }

    pub fn removeChildAt(self: *Node, index: usize) ?*Node {
        if (index >= self.children.items.len) return null;
        const child = self.children.orderedRemove(index);
        child.parent = null;
        return child;
    }

    pub fn replaceChild(self: *Node, old_child: *Node, new_child: *Node) !void {
        for (self.children.items, 0..) |c, i| {
            if (c == old_child) {
                old_child.parent = null;
                new_child.parent = self;
                self.children.items[i] = new_child;
                return;
            }
        }
        return error.ChildNotFound;
    }

    pub fn getAttribute(self: *Node, name: []const u8) ?[]const u8 {
        return self.attributes.get(name);
    }

    pub fn setAttribute(self: *Node, name: []const u8, value: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_value = try self.allocator.dupe(u8, value);
        if (self.attributes.get(owned_name)) |old_value| {
            self.allocator.free(old_value);
            self.allocator.free(owned_name);
        }
        try self.attributes.put(owned_name, owned_value);
    }

    pub fn removeAttribute(self: *Node, name: []const u8) void {
        if (self.attributes.remove(name)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }

    pub fn getAttributes(self: *Node) StringHashMap([]const u8) {
        return self.attributes;
    }

    pub fn findChildByTag(self: *Node, tag: []const u8) ?*Node {
        for (self.children.items) |child| {
            if (child.node_type == .Element and child.name != null and std.mem.eql(u8, child.name.?, tag)) {
                return child;
            }
        }
        return null;
    }

    pub fn getChildrenByTag(self: *Node, tag: []const u8) ChildIterator {
        return ChildIterator{ .node = self, .tag = tag, .index = 0 };
    }

    pub fn getParent(self: *Node) ?*Node {
        return self.parent;
    }

    pub fn getNextSibling(self: *Node) ?*Node {
        if (self.parent) |parent| {
            for (parent.children.items, 0..) |child, i| {
                if (child == self and i + 1 < parent.children.items.len) {
                    return parent.children.items[i + 1];
                }
            }
        }
        return null;
    }

    pub fn getPreviousSibling(self: *Node) ?*Node {
        if (self.parent) |parent| {
            for (parent.children.items, 0..) |child, i| {
                if (child == self and i > 0) {
                    return parent.children.items[i - 1];
                }
            }
        }
        return null;
    }

    pub fn getFirstChild(self: *Node) ?*Node {
        return if (self.children.items.len > 0) self.children.items[0] else null;
    }

    pub fn getLastChild(self: *Node) ?*Node {
        return if (self.children.items.len > 0) self.children.items[self.children.items.len - 1] else null;
    }

    pub fn getChildCount(self: *Node) usize {
        return self.children.items.len;
    }

    pub fn findDescendantByTag(self: *Node, tag: []const u8) ?*Node {
        if (self.node_type == .Element and self.name != null and std.mem.eql(u8, self.name.?, tag)) {
            return self;
        }
        for (self.children.items) |child| {
            if (child.findDescendantByTag(tag)) |found| {
                return found;
            }
        }
        return null;
    }

    pub fn toString(self: *Node, allocator: Allocator) ![]u8 {
        var buffer = ArrayList(u8).init(allocator);
        defer buffer.deinit();
        try self.writeToString(&buffer);
        return buffer.toOwnedSlice();
    }

    fn appendToString(self: *Node, buffer: *ArrayList(u8)) !void {
        switch (self.node_type) {
            .Element => {
                try buffer.appendSlice("<");
                try buffer.appendSlice(self.name.?);
                var it = self.attributes.iterator();
                while (it.next()) |entry| {
                    try buffer.appendSlice(" ");
                    try buffer.appendSlice(entry.key_ptr.*);
                    try buffer.appendSlice("=\"");
                    try buffer.appendSlice(entry.value_ptr.*);
                    try buffer.appendSlice("\"");
                }
                if (self.children.items.len == 0 and self.text == null) {
                    try buffer.appendSlice("/>");
                } else {
                    try buffer.appendSlice(">");
                    if (self.text) |text| {
                        try buffer.appendSlice(text);
                    }
                    for (self.children.items) |child| {
                        try child.appendToString(buffer);
                    }
                    try buffer.appendSlice("</");
                    try buffer.appendSlice(self.name.?);
                    try buffer.appendSlice(">");
                }
            },
            .Text => {
                if (self.text) |text| {
                    try buffer.appendSlice(text);
                }
            },
            .Comment => {
                try buffer.appendSlice("<!--");
                if (self.text) |text| {
                    try buffer.appendSlice(text);
                }
                try buffer.appendSlice("-->");
            },
            .Document => {
                for (self.children.items) |child| {
                    try child.appendToString(buffer);
                }
            },
        }
    }

    pub fn clone(self: *Node, allocator: Allocator) !*Node {
        const new_node = try Node.init(allocator, self.node_type, self.name, self.text);
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            try new_node.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
        }
        for (self.children.items) |child| {
            const cloned_child = try child.clone(allocator);
            try new_node.appendChild(cloned_child);
        }
        return new_node;
    }
};

pub const ChildIterator = struct {
    node: *Node,
    tag: []const u8,
    index: usize,

    pub fn next(self: *ChildIterator) ?*Node {
        while (self.index < self.node.children.items.len) {
            const child = self.node.children.items[self.index];
            self.index += 1;
            if (child.node_type == .Element and child.name != null and std.mem.eql(u8, child.name.?, self.tag)) {
                return child;
            }
        }
        return null;
    }
};

pub const Parser = struct {
    allocator: Allocator,
    input: []const u8,
    pos: usize,

    pub fn init(allocator: Allocator, input: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .input = input,
            .pos = 0,
        };
    }

    pub fn parse(self: *Parser) !*Node {
        const document = try Node.init(self.allocator, .Document, null, null);
        errdefer document.deinit();

        log("Parsing XML document, input length: {d}\n", .{self.input.len});
        while (self.pos < self.input.len) {
            self.skipWhitespace();
            if (self.pos >= self.input.len) break;

            if (self.input[self.pos] == '<') {
                if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '?') {
                    log("Skipping processing instruction at pos: {d}\n", .{self.pos});
                    self.skipProcessingInstruction();
                } else if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '!') {
                    log("Skipping comment at pos: {d}\n", .{self.pos});
                    self.skipComment();
                } else {
                    log("Parsing element at pos: {d}\n", .{self.pos});
                    const node = try self.parseElement();
                    try document.appendChild(node);
                    log("Appended element: {s}\n", .{node.name orelse "unnamed"});
                }
            }
        }
        log("Finished parsing, document has {d} children\n", .{document.children.items.len});
        return document;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    fn skipProcessingInstruction(self: *Parser) void {
        while (self.pos < self.input.len and self.input[self.pos] != '>' and
               (self.pos + 1 < self.input.len and
               self.input[self.pos] != '?' or self.input[self.pos + 1] != '>')) {
            self.pos += 1;
        }
        if (self.pos + 1 < self.input.len and self.input[self.pos] == '?' and self.input[self.pos + 1] == '>') {
            self.pos += 2;
        } else {
            log("Invalid processing instruction at pos: {d}\n", .{self.pos});
        }
    }

    fn skipComment(self: *Parser) void {
        while (self.pos < self.input.len and self.input[self.pos] != '>' and
               (self.pos + 2 < self.input.len and
               self.input[self.pos] != '-' or
               self.input[self.pos + 1] != '-' or
               self.input[self.pos + 2] != '>')) {
            self.pos += 1;
        }
        if (self.pos + 2 < self.input.len and
            self.input[self.pos] == '-' and
            self.input[self.pos + 1] == '-' and
            self.input[self.pos + 2] == '>') {
            self.pos += 3;
        } else {
            log("Invalid comment at pos: {d}\n", .{self.pos});
        }
    }

    fn parseElement(self: *Parser) !*Node {
        if (self.pos >= self.input.len or self.input[self.pos] != '<') {
            log("Invalid XML: Expected '<' at pos: {d}\n", .{self.pos});
            return error.InvalidXml;
        }
        self.pos += 1;

        const name_start = self.pos;
        while (self.pos < self.input.len and
               !std.ascii.isWhitespace(self.input[self.pos]) and
               self.input[self.pos] != '>' and self.input[self.pos] != '/') {
            self.pos += 1;
        }
        const name = self.input[name_start..self.pos];
        if (name.len == 0) {
            log("Invalid XML: Empty tag name at pos: {d}\n", .{name_start});
            return error.InvalidXml;
        }

        log("Parsing element: {s}\n", .{name});
        const element = try Node.init(self.allocator, .Element, name, null);
        errdefer element.deinit();

        while (self.pos < self.input.len and self.input[self.pos] != '>' and self.input[self.pos] != '/') {
            self.skipWhitespace();
            if (self.pos >= self.input.len or self.input[self.pos] == '>' or self.input[self.pos] == '/') break;

            const attr_name_start = self.pos;
            while (self.pos < self.input.len and
                   self.input[self.pos] != '=' and
                   !std.ascii.isWhitespace(self.input[self.pos]) and
                   self.input[self.pos] != '>' and
                   self.input[self.pos] != '/') {
                self.pos += 1;
            }
            const attr_name = self.input[attr_name_start..self.pos];
            if (attr_name.len == 0) {
                log("Invalid XML: Empty attribute name at pos: {d}\n", .{attr_name_start});
                return error.InvalidXml;
            }

            self.skipWhitespace();
            if (self.pos >= self.input.len or self.input[self.pos] != '=') {
                log("Invalid XML: Expected '=' after attribute {s} at pos: {d}\n", .{attr_name, self.pos});
                return error.InvalidXml;
            }
            self.pos += 1;
            self.skipWhitespace();
            if (self.pos >= self.input.len or self.input[self.pos] != '"') {
                log("Invalid XML: Expected '\"' for attribute value at pos: {d}\n", .{self.pos});
                return error.InvalidXml;
            }
            self.pos += 1;

            const attr_value_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] != '"') {
                self.pos += 1;
            }
            if (self.pos >= self.input.len) {
                log("Invalid XML: Unclosed attribute value at pos: {d}\n", .{attr_value_start});
                return error.InvalidXml;
            }
            const attr_value = self.input[attr_value_start..self.pos];
            self.pos += 1;

            log("Parsed attribute: {s}=\"{s}\"\n", .{attr_name, attr_value});
            try element.setAttribute(attr_name, attr_value);
        }

        if (self.pos >= self.input.len) {
            log("Invalid XML: Unexpected end of input in element {s}\n", .{name});
            return error.InvalidXml;
        }

        if (self.input[self.pos] == '/') {
            if (self.pos + 1 >= self.input.len or self.input[self.pos + 1] != '>') {
                log("Invalid XML: Invalid self-closing tag {s} at pos: {d}\n", .{name, self.pos});
                return error.InvalidXml;
            }
            self.pos += 2;
            log("Parsed self-closing element: {s}\n", .{name});
            return element;
        }

        if (self.input[self.pos] != '>') {
            log("Invalid XML: Expected '>' after element {s} at pos: {d}\n", .{name, self.pos});
            return error.InvalidXml;
        }
        self.pos += 1;

        while (self.pos < self.input.len) {
            self.skipWhitespace();
            if (self.pos >= self.input.len) {
                log("Invalid XML: Unexpected end of input in element {s}\n", .{name});
                return error.InvalidXml;
            }

            if (self.input[self.pos] == '<' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '/') {
                self.pos += 2;
                const end_tag_start = self.pos;
                while (self.pos < self.input.len and self.input[self.pos] != '>') {
                    self.pos += 1;
                }
                const end_tag = self.input[end_tag_start..self.pos];
                if (!std.mem.eql(u8, end_tag, name)) {
                    log("Invalid XML: Mismatched closing tag, expected {s}, got {s}\n", .{name, end_tag});
                    return error.InvalidXml;
                }
                if (self.pos >= self.input.len) {
                    log("Invalid XML: Missing '>' for closing tag {s}\n", .{name});
                    return error.InvalidXml;
                }
                self.pos += 1;
                break;
            } else if (self.input[self.pos] == '<' and self.pos + 1 < self.input.len and self.input[self.pos + 1] == '!') {
                log("Skipping comment in element {s}\n", .{name});
                self.skipComment();
            } else if (self.input[self.pos] == '<') {
                const child = try self.parseElement();
                try element.appendChild(child);
                log("Appended child element: {s} to {s}\n", .{child.name orelse "unnamed", name});
            } else {
                const text_start = self.pos;
                while (self.pos < self.input.len and self.input[self.pos] != '<') {
                    self.pos += 1;
                }
                const text = std.mem.trim(u8, self.input[text_start..self.pos], " \n\t");
                if (text.len > 0) {
                    const text_node = try Node.init(self.allocator, .Text, null, text);
                    try element.appendChild(text_node);
                    log("Appended text node: {s} to {s}\n", .{text, name});
                }
            }
        }

        return element;
    }
};
