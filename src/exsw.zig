const std = @import("std");
pub const rl = @import("raylib");
pub const rg = @import("raygui");
pub const channels = @import("channels.zig");
pub const xml = @import("xml.zig");
pub const dom = @import("dom.zig");
pub const listeners = @import("listener.zig");
pub const esl = @import("esl.zig");
pub const element = @import("element.zig");

const State = struct {
    gap_y: i32,
    gap_x: i32,
    document: ?*xml.Node,
    dom: ?dom.DOM,
};

pub var state = State {
    .gap_y = 24,
    .gap_x = 5,
    .document = null,
    .dom = null,
};

pub const WindowEventType = enum {
    BUTTON_CLICK,
    CHECKBOX_CHECKED,
};

pub const WindowEvent = struct {
    id: []const u8,
    type: WindowEventType,
    element: ?*element.Element = null,
};

pub var windowEvents = listeners.EventListener(WindowEventType, WindowEvent).init(std.heap.page_allocator);

fn parseColor(color: ?[]const u8) rl.Color {
    if (color) |c| {
        if (std.mem.eql(u8, c, "red")) return rl.Color.red;
        if (std.mem.eql(u8, c, "green")) return rl.Color.green;
        if (std.mem.eql(u8, c, "blue")) return rl.Color.blue;
        if (std.mem.eql(u8, c, "white")) return rl.Color.white;
        if (std.mem.eql(u8, c, "black")) return rl.Color.black;
        return rl.Color.black;
    } else return rl.Color.black; 
}

pub fn stringToCstrFixed(comptime max_len: usize, str: []const u8) [max_len:0]u8 {
    if (str.len >= max_len) @panic("String too large for buffer");
    var cstr: [max_len:0]u8 = undefined;
    @memcpy(cstr[0..str.len], str);
    cstr[str.len] = 0;
    return cstr;
}

fn xmlNodeToElement(allocator: std.mem.Allocator, node: *xml.Node) !*element.Element {
    const element_type = if (node.name) |name| blk: {
        if (std.mem.eql(u8, name, "window")) break :blk element.ElementType.Window;
        if (std.mem.eql(u8, name, "label")) break :blk element.ElementType.Label;
        if (std.mem.eql(u8, name, "button")) break :blk element.ElementType.Button;
        if (std.mem.eql(u8, name, "checkbox")) break :blk element.ElementType.Checkbox;
        if (node.node_type == .Text) break :blk element.ElementType.Text;
        std.debug.print("Unsupported XML tag: {s}\n", .{name});
        return error.UnsupportedTag;
    } else if (node.node_type == .Text) element.ElementType.Text else return error.InvalidNode;

    const id = node.getAttribute("id");
    const text = if (node.node_type == .Text) node.text else node.getAttribute("text");
    
    var elem = try element.Element.init(allocator, element_type, id, text);
    errdefer elem.deinit();

    var it = node.getAttributes().iterator();
    while (it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "id") and !std.mem.eql(u8, entry.key_ptr.*, "text")) {
            try elem.setAttribute(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    for (node.children.items) |child| {
        if (child.node_type == .Element or child.node_type == .Text) {
            const child_elem = try xmlNodeToElement(allocator, child);
            try elem.appendChild(child_elem);
        }
    }

    return elem;
}

pub fn initEXSW(width: i32, height: i32) void {
    rl.setTraceLogLevel(.none);
    
    rl.initWindow(width, height, "No Title");
    rl.initAudioDevice();
}

pub fn renderFile(filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(std.heap.page_allocator, 1024*1024);
    defer std.heap.page_allocator.free(file_content);

    var parser = xml.Parser.init(std.heap.page_allocator, file_content);
    state.document = try parser.parse();

    if (state.document.?.findChildByTag("window")) |window_node| {
        const root_elem = try xmlNodeToElement(std.heap.page_allocator, window_node);
        state.dom = dom.DOM.init(std.heap.page_allocator, root_elem);
        
        if (root_elem.getAttribute("title")) |title| {
            rl.setWindowTitle(&stringToCstrFixed(1024, title));
        }
    } else {
        return error.NoWindowElement;
    }
}

pub fn renderDocument() void {
    if (state.dom == null) return;

    rl.beginDrawing();
    defer rl.endDrawing();
    
    var bg_color = rl.Color.white;

    state.gap_y = 24;
    state.gap_x = 5;
    if (state.dom.?.querySelector("window")) |window| {
        if (window.getAttribute("style")) |style_str| {
            var window_style = blk: {
                var parser = esl.Parser.init(std.heap.page_allocator, style_str);
                break :blk parser.parse() catch esl.Style{};
            };
            defer window_style.deinit();
            
            if (window_style.background) |bg| {
                bg_color = parseColor(bg);
            }
        }
        rl.clearBackground(bg_color);
        for (window.children.items) |node| {
            var style = if (node.getAttribute("style")) |style_str| blk: {
                var parser = esl.Parser.init(std.heap.page_allocator, style_str);
                break :blk parser.parse() catch esl.Style{};
            } else esl.Style{};
            defer style.deinit();

            if (node.element_type == .Text and node.text != null) {
                rl.drawText(&stringToCstrFixed(1024, node.text.?), 
                    style.pos_x orelse state.gap_x, 
                    style.pos_y orelse state.gap_y, 
                    style.font_size orelse 24, 
                    parseColor(style.color));
                if (style.pos_y == null) state.gap_y += style.height orelse 28;
            } else if (node.element_type == .Label) {
                if (node.getAttribute("text")) |text| {
                    rl.drawText(&stringToCstrFixed(1024, text), 
                        style.pos_x orelse state.gap_x, 
                        style.pos_y orelse state.gap_y, 
                        style.font_size orelse 24, 
                        parseColor(style.color));
                    if (style.pos_y == null) state.gap_y += style.height orelse 28;
                }
            } else if (node.element_type == .Button) {
                const id = node.id orelse "";
                if (style.background) |bg| {
                    rl.drawRectangle(
                        style.pos_x orelse state.gap_x, 
                        style.pos_y orelse state.gap_y, 
                        style.width orelse 100, 
                        style.height orelse 24, 
                        parseColor(bg));
                }
                const button_text = if (node.children.items.len > 0 and node.children.items[0].text != null) 
                    node.children.items[0].text.? else "";
                if (rg.button(.{ 
                    .height = @floatFromInt(style.height orelse 24), 
                    .width = @floatFromInt(style.width orelse 100), 
                    .x = @floatFromInt(style.pos_x orelse state.gap_x), 
                    .y = @floatFromInt(style.pos_y orelse state.gap_y)
                }, &stringToCstrFixed(1024, button_text))) 
                    windowEvents.emit(.BUTTON_CLICK, .{ .id = id, .type = .BUTTON_CLICK });
                if (style.pos_y == null) state.gap_y += style.height orelse 28;
            } else if (node.element_type == .Checkbox) {
                const id = node.id orelse "";
                if (style.background) |bg| {
                    rl.drawRectangle(
                        style.pos_x orelse state.gap_x, 
                        style.pos_y orelse state.gap_y, 
                        style.width orelse 24, 
                        style.height orelse 24, 
                        parseColor(bg));
                }
                var checked = (node.getState("checked") orelse "false").len > 0 and std.mem.eql(u8, node.getState("checked").?, "true");
                const checkbox_text = if (node.children.items.len > 0 and node.children.items[0].text != null) 
                    node.children.items[0].text.? else "";
                if (rg.checkBox(.{ 
                    .height = @floatFromInt(style.height orelse 24), 
                    .width = @floatFromInt(style.width orelse 24), 
                    .x = @floatFromInt(style.pos_x orelse state.gap_x), 
                    .y = @floatFromInt(style.pos_y orelse state.gap_y)
                }, &stringToCstrFixed(1024, checkbox_text), &checked)) {
                    if (node.setState("checked", if (checked) "true" else "false")) |_| {
                        windowEvents.emit(.CHECKBOX_CHECKED, .{ .id = id, .element = node, .type = .CHECKBOX_CHECKED });
                    } else |err| {
                        std.debug.print("Failed to set checkbox state for id '{s}': {}\n", .{id, err});
                    } 
                }
                if (style.pos_y == null) state.gap_y += style.height orelse 28;
            } else {
                std.debug.print("Element type '{}' not supported\n", .{node.element_type});
            }
        }
    }
}

pub fn closeEXSW() void {
    if (state.dom) |*d| {
        d.deinit();
        state.dom = null;
    }
    if (state.document) |*doc| {
        doc.*.deinit();
        state.document = null;
    }
    rl.closeAudioDevice();
    rl.closeWindow();
}

pub fn addLabel(id: []const u8, text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    const node = try state.dom.?.createElement(.Label, id, null);
    try state.dom.?.setAttribute(id, "text", text);
    if (style) |s| try state.dom.?.setAttribute(id, "style", s);
    try state.dom.?.appendChild("window", node);
}

pub fn addButton(id: []const u8, text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    var node = try state.dom.?.createElement(.Button, id, null);
    if (style) |s| try state.dom.?.setAttribute(id, "style", s);
    const text_node = try state.dom.?.createElement(.Text, null, text);
    try node.appendChild(text_node);
    try state.dom.?.appendChild("window", node);
}

pub fn addText(text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    var node = try state.dom.?.createElement(.Text, null, text);
    if (style) |s| try node.setAttribute("style", s);
    try state.dom.?.appendChild("window", node);
}

pub fn addCheckbox(id: []const u8, text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    var node = try state.dom.?.createElement(.Checkbox, id, null);
    if (style) |s| try state.dom.?.setAttribute(id, "style", s);
    const text_node = try state.dom.?.createElement(.Text, null, text);
    try node.appendChild(text_node);
    try state.dom.?.appendChild("window", node);
}

pub fn updateElementText(id: []const u8, new_text: []const u8) !void {
    if (state.dom == null) return error.NoDom;
    if (state.dom.?.getElementById(id)) |elem| {
        if (elem.element_type == .Label) {
            try state.dom.?.setAttribute(id, "text", new_text);
        } else if (elem.element_type == .Button or elem.element_type == .Checkbox) {
            if (elem.children.items.len > 0) {
                try state.dom.?.setTextContent(elem.children.items[0].id orelse return error.NoTextNode, new_text);
            } else {
                const text_node = try state.dom.?.createElement(.Text, null, new_text);
                try elem.appendChild(text_node);
            }
        } else {
            try state.dom.?.setTextContent(id, new_text);
        }
    } else {
        return error.ElementNotFound;
    }
}

pub fn updateElementStyle(id: []const u8, new_style: []const u8) !void {
    if (state.dom == null) return error.NoDom;
    try state.dom.?.setAttribute(id, "style", new_style);
}

pub fn removeElement(id: []const u8) !void {
    if (state.dom == null) return error.NoDom;
    try state.dom.?.removeChild("window", id);
}

pub fn setWindowTitle(title: []const u8) void {
    rl.setWindowTitle(&stringToCstrFixed(1024, title));
    if (state.dom) |*d| {
        d.setAttribute("window", "title", title) catch return;
    }
}

pub fn getElementText(id: []const u8) ?[]const u8 {
    if (state.dom == null) return null;
    if (state.dom.?.getElementById(id)) |elem| {
        if (elem.element_type == .Label) {
            return elem.getAttribute("text");
        } else if (elem.element_type == .Button or elem.element_type == .Checkbox) {
            if (elem.children.items.len > 0) {
                return elem.children.items[0].text;
            }
        } else {
            return elem.text;
        }
    }
    return null;
}
