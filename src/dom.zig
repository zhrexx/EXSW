const std = @import("std");
const xml = @import("xml.zig");

pub const DOM = struct {
    document: *xml.Node,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, document: *xml.Node) DOM {
        return .{
            .document = document,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DOM) void {
        self.document.deinit();
        self.allocator.destroy(self.document);
    }

    pub fn createElement(self: *DOM, tag: []const u8) !*xml.Node {
        return try xml.Node.init(self.allocator, .Element, tag, null);
    }

    pub fn createTextNode(self: *DOM, text: []const u8) !*xml.Node {
        return try xml.Node.init(self.allocator, .Text, null, text);
    }

    pub fn getElementById(self: *DOM, id: []const u8) ?*xml.Node {
        return self.findElementById(self.document, id);
    }

    fn findElementById(self: *DOM, node: *xml.Node, id: []const u8) ?*xml.Node {
        if (node.node_type == .Element) {
            if (node.getAttribute("id")) |node_id| {
                if (std.mem.eql(u8, node_id, id)) {
                    return node;
                }
            }
        }
        for (node.children.items) |child| {
            if (self.findElementById(child, id)) |found| {
                return found;
            }
        }
        return null;
    }

    pub fn getElementsByTagName(self: *DOM, tag: []const u8) std.ArrayList(*xml.Node) {
        var result = std.ArrayList(*xml.Node).init(self.allocator);
        self.collectElementsByTagName(self.document, tag, &result);
        return result;
    }

    fn collectElementsByTagName(self: *DOM, node: *xml.Node, tag: []const u8, result: *std.ArrayList(*xml.Node)) void {
        if (node.node_type == .Element and node.name != null and std.mem.eql(u8, node.name.?, tag)) {
            result.append(node) catch return;
        }
        for (node.children.items) |child| {
            self.collectElementsByTagName(child, tag, result);
        }
    }

    pub fn querySelector(self: *DOM, selector: []const u8) ?*xml.Node {
        if (selector.len > 0 and selector[0] == '#') {
            return self.getElementById(selector[1..]);
        }
        if (self.document.findChildByTag(selector)) |node| {
            return node;
        }
        return self.document.findDescendantByTag(selector);
    }

    pub fn querySelectorAll(self: *DOM, selector: []const u8) std.ArrayList(*xml.Node) {
        var result = std.ArrayList(*xml.Node).init(self.allocator);
        if (selector.len > 0 and selector[0] == '#') {
            if (self.getElementById(selector[1..])) |node| {
                result.append(node) catch return result;
            }
        } else {
            return self.getElementsByTagName(selector);
        }
        return result;
    }

    pub fn appendChild(self: *DOM, parent_id: []const u8, child: *xml.Node) !void {
        if (self.getElementById(parent_id)) |parent| {
            try parent.appendChild(child);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn removeChild(self: *DOM, parent_id: []const u8, child_id: []const u8) !void {
        if (self.getElementById(parent_id)) |parent| {
            if (self.getElementById(child_id)) |child| {
                parent.removeChild(child);
            } else {
                return error.ChildNotFound;
            }
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn setAttribute(self: *DOM, id: []const u8, name: []const u8, value: []const u8) !void {
        if (self.getElementById(id)) |element| {
            try element.setAttribute(name, value);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn getAttribute(self: *DOM, id: []const u8, name: []const u8) ?[]const u8 {
        if (self.getElementById(id)) |element| {
            return element.getAttribute(name);
        }
        return null;
    }

    pub fn removeAttribute(self: *DOM, id: []const u8, name: []const u8) !void {
        if (self.getElementById(id)) |element| {
            element.removeAttribute(name);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn setTextContent(self: *DOM, id: []const u8, text: []const u8) !void {
        if (self.getElementById(id)) |element| {
            if (element.node_type == .Text) {
                if (element.text) |old_text| {
                    self.allocator.free(old_text);
                }
                element.text = try self.allocator.dupe(u8, text);
            } else {
                for (element.children.items) |child| {
                    child.deinit();
                    self.allocator.destroy(child);
                }
                element.children.clearAndFree();
                const text_node = try self.createTextNode(text);
                try element.appendChild(text_node);
            }
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn getTextContent(self: *DOM, id: []const u8) ?[]const u8 {
        if (self.getElementById(id)) |element| {
            if (element.node_type == .Text) {
                return element.text;
            }
            if (element.children.items.len > 0 and element.children.items[0].node_type == .Text) {
                return element.children.items[0].text;
            }
        }
        return null;
    }

    pub fn addEventListener(self: *DOM, id: []const u8, event_type: []const u8, listener: *const fn([]const u8) void) !void {
        _ = self;
        _ = id;
        _ = event_type;
        _ = listener;
    }

    pub fn removeEventListener(self: *DOM, id: []const u8, event_type: []const u8, listener: *const fn([]const u8) void) void {
        _ = self;
        _ = id;
        _ = event_type;
        _ = listener;
    }
};
