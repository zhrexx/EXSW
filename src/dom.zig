const std = @import("std");
const element = @import("element.zig");
const listeners = @import("listener.zig");

pub const DOM = struct {
    root: *element.Element,
    allocator: std.mem.Allocator,
    event_listeners: listeners.EventListener([]const u8, EventData),

    pub const EventData = struct {
        element_id: []const u8,
        data: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, root: *element.Element) DOM {
        return .{
            .root = root,
            .allocator = allocator,
            .event_listeners = listeners.EventListener([]const u8, EventData).init(allocator),
        };
    }

    pub fn deinit(self: *DOM) void {
        self.event_listeners.deinit();
        self.root.deinit();
        self.allocator.destroy(self.root);
    }

    pub fn createElement(self: *DOM, element_type: element.ElementType, id: ?[]const u8, text: ?[]const u8) !*element.Element {
        return try element.Element.init(self.allocator, element_type, id, text);
    }

    pub fn getElementById(self: *DOM, id: []const u8) ?*element.Element {
        return self.root.findChildById(id);
    }

    pub fn getElementsByType(self: *DOM, element_type: element.ElementType) std.ArrayList(*element.Element) {
        return self.root.findChildrenByType(element_type);
    }

    pub fn querySelector(self: *DOM, selector: []const u8) ?*element.Element {
        if (selector.len > 0 and selector[0] == '#') {
            return self.getElementById(selector[1..]);
        }
        var elements = self.getElementsByType(.Window);
        defer elements.deinit();
        return if (elements.items.len > 0) elements.items[0] else null;
    }

    pub fn querySelectorAll(self: *DOM, selector: []const u8) std.ArrayList(*element.Element) {
        var result = std.ArrayList(*element.Element).init(self.allocator);
        if (selector.len > 0 and selector[0] == '#') {
            if (self.getElementById(selector[1..])) |elem| {
                result.append(elem) catch return result;
            }
        } else {
            var elements = self.getElementsByType(.Window);
            result.appendSlice(elements.items) catch {};
            elements.deinit();
        }
        return result;
    }

    pub fn appendChild(self: *DOM, parent_id: []const u8, child: *element.Element) !void {
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
                return error.ElementNotFound;
            }
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn setAttribute(self: *DOM, id: []const u8, name: []const u8, value: []const u8) !void {
        if (self.getElementById(id)) |elem| {
            try elem.setAttribute(name, value);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn getAttribute(self: *DOM, id: []const u8, name: []const u8) ?[]const u8 {
        if (self.getElementById(id)) |elem| {
            return elem.getAttribute(name);
        }
        return null;
    }

    pub fn setTextContent(self: *DOM, id: []const u8, text: []const u8) !void {
        if (self.getElementById(id)) |elem| {
            if (elem.text) |old_text| {
                self.allocator.free(old_text);
            }
            elem.text = try self.allocator.dupe(u8, text);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn getTextContent(self: *DOM, id: []const u8) ?[]const u8 {
        if (self.getElementById(id)) |elem| {
            return elem.text;
        }
        return null;
    }

    pub fn setElementState(self: *DOM, id: []const u8, key: []const u8, value: []const u8) !void {
        if (self.getElementById(id)) |elem| {
            try elem.setState(key, value);
        } else {
            return error.ElementNotFound;
        }
    }

    pub fn getElementState(self: *DOM, id: []const u8, key: []const u8) ?[]const u8 {
        if (self.getElementById(id)) |elem| {
            return elem.getState(key);
        }
        return null;
    }

    pub fn addEventListener(self: *DOM, id: []const u8, event_type: []const u8, listener: *const fn(EventData) void) !void {
        try self.event_listeners.addListener(event_type, listener);
        _ = id;
    }

    pub fn removeEventListener(self: *DOM, id: []const u8, event_type: []const u8, listener: *const fn(EventData) void) void {
        self.event_listeners.removeListener(event_type, listener);
        _ = id;
    }
};
