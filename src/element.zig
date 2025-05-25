const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const esl = @import("esl.zig");

pub const ElementType = enum {
    Window,
    Label,
    Button,
    Checkbox,
    Text,
};

pub const ElementState = struct {
    values: StringHashMap([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ElementState {
        return .{ .values = StringHashMap([]const u8).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *ElementState) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.values.deinit();
    }

    pub fn set(self: *ElementState, key: []const u8, value: []const u8) !void {
        if (self.values.getEntry(key)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            const owned_value = try self.allocator.dupe(u8, value);
            entry.value_ptr.* = owned_value;
        } else {
            const owned_key = try self.allocator.dupe(u8, key);
            const owned_value = try self.allocator.dupe(u8, value);
            try self.values.put(owned_key, owned_value);
        }
    }

    pub fn get(self: *ElementState, key: []const u8) ?[]const u8 {
        return self.values.get(key);
    }

    pub fn remove(self: *ElementState, key: []const u8) void {
        if (self.values.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }
};

pub const Element = struct {
    id: ?[]const u8,
    element_type: ElementType,
    text: ?[]const u8,
    style: esl.Style,
    attributes: StringHashMap([]const u8),
    state: ElementState,
    children: std.ArrayList(*Element),
    allocator: Allocator,
    parent: ?*Element,

    pub fn init(allocator: Allocator, element_type: ElementType, id: ?[]const u8, text: ?[]const u8) !*Element {
        const element = try allocator.create(Element);
        element.* = .{
            .id = if (id) |i| try allocator.dupe(u8, i) else null,
            .element_type = element_type,
            .text = if (text) |t| try allocator.dupe(u8, t) else null,
            .style = esl.Style.init(allocator),
            .attributes = StringHashMap([]const u8).init(allocator),
            .state = ElementState.init(allocator),
            .children = std.ArrayList(*Element).init(allocator),
            .allocator = allocator,
            .parent = null,
        };
        if (element_type == .Checkbox) {
            try element.state.set("checked", "false");
        }
        return element;
    }

    pub fn deinit(self: *Element) void {
        if (self.id) |i| self.allocator.free(i);
        if (self.text) |t| self.allocator.free(t);
        self.style.deinit();
        self.state.deinit();
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

    pub fn appendChild(self: *Element, child: *Element) !void {
        child.parent = self;
        try self.children.append(child);
    }

    pub fn removeChild(self: *Element, child: *Element) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                child.parent = null;
                _ = self.children.orderedRemove(i);
                return;
            }
        }
    }

    pub fn setAttribute(self: *Element, name: []const u8, value: []const u8) !void {
        if (self.attributes.getEntry(name)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            const owned_value = try self.allocator.dupe(u8, value);
            entry.value_ptr.* = owned_value;
        } else {
            const owned_name = try self.allocator.dupe(u8, name);
            const owned_value = try self.allocator.dupe(u8, value);
            try self.attributes.put(owned_name, owned_value);
        }
    }

    pub fn getAttribute(self: *Element, name: []const u8) ?[]const u8 {
        return self.attributes.get(name);
    }

    pub fn removeAttribute(self: *Element, name: []const u8) void {
        if (self.attributes.fetchRemove(name)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }

    pub fn setStyle(self: *Element, style_str: []const u8) !void {
        var parser = esl.Parser.init(self.allocator, style_str);
        self.style.deinit();
        self.style = try parser.parse();
    }

    pub fn setState(self: *Element, key: []const u8, value: []const u8) !void {
        try self.state.set(key, value);
    }

    pub fn getState(self: *Element, key: []const u8) ?[]const u8 {
        return self.state.get(key);
    }

    pub fn findChildById(self: *Element, id: []const u8) ?*Element {
        if (self.id) |self_id| {
            if (std.mem.eql(u8, self_id, id)) return self;
        }
        for (self.children.items) |child| {
            if (child.findChildById(id)) |found| {
                return found;
            }
        }
        return null;
    }

    pub fn findChildrenByType(self: *Element, element_type: ElementType) std.ArrayList(*Element) {
        var result = std.ArrayList(*Element).init(self.allocator);
        if (self.element_type == element_type) {
            result.append(self) catch return result;
        }
        for (self.children.items) |child| {
            var child_results = child.findChildrenByType(element_type);
            result.appendSlice(child_results.items) catch {};
            child_results.deinit();
        }
        return result;
    }
};
