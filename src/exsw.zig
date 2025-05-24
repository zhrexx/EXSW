// TODO: add more elements

const std = @import("std");
pub const rl = @import("raylib");
pub const rg = @import("raygui");
pub const channels = @import("channels.zig");
pub const xml = @import("xml.zig");
pub const dom = @import("dom.zig");
pub const listeners = @import("listener.zig");
pub const esl = @import("esl.zig");

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
};

pub const WindowEvent = struct {
    id: []const u8,
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

pub fn initEXSW(width: i32, height: i32) void {
    rl.initWindow(width, height, "No Title");
    rl.initAudioDevice();
}

pub fn renderFile(filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(std.heap.page_allocator, 1024*1024);
    var parser = xml.Parser.init(std.heap.page_allocator, file_content);
    defer std.heap.page_allocator.free(file_content);

    state.document = try parser.parse();
    state.dom = dom.DOM.init(std.heap.page_allocator, state.document.?);

    if (state.dom.?.querySelector("window")) |window| {
        if (window.getAttribute("title")) |title| {
            rl.setWindowTitle(&stringToCstrFixed(1024, title));
        }
    }
}

pub fn renderDocument() void {
    if (state.dom == null or state.document == null) return;

    rl.beginDrawing();
    rl.clearBackground(rl.Color.white);

    state.gap_y = 24;
    state.gap_x = 5;
    if (state.dom.?.querySelector("window")) |window| {
        for (window.children.items) |node| {
            var style = if (node.getAttribute("style")) |style_str| blk: {
                var parser = esl.Parser.init(std.heap.page_allocator, style_str);
                break :blk parser.parse() catch esl.Style{};
            } else esl.Style{};
            defer style.deinit();

            if (node.node_type == .Text and node.text != null) {
                rl.drawText(&stringToCstrFixed(1024, node.text.?), state.gap_x, state.gap_y, 
                    style.font_size orelse 24, parseColor(style.color));
                if (style.pos_y == null) state.gap_y += 28;
            } else if (node.name) |tag| {
                const id = node.getAttribute("id") orelse "";
                if (std.mem.eql(u8, tag, "label")) {
                    if (node.getAttribute("text")) |text| {
                        rl.drawText(&stringToCstrFixed(1024, text), style.pos_x orelse state.gap_x, style.pos_y orelse state.gap_y, 
                            style.font_size orelse 24, parseColor(style.color));
                        if (style.pos_y == null) state.gap_y += 28;
                    }
                } else if (std.mem.eql(u8, tag, "button")) {
                    if (style.background) |bg| {
                        rl.drawRectangle(state.gap_x, state.gap_y, 100, 24, parseColor(bg));
                    }
                    if (rg.button(.{ .height = 24, .width = 100, .x = @floatFromInt(state.gap_x), .y = @floatFromInt(state.gap_y)}, 
                            &stringToCstrFixed(1024, node.children.items[0].text orelse ""))) windowEvents.emit(.BUTTON_CLICK, .{ .id = id });
                    if (style.pos_y == null) state.gap_y += 28;
                }
            }
        }
    }
    rl.endDrawing();
}

pub fn closeEXSW() void {
    if (state.dom) |*d| {
        d.deinit();
        state.dom = null;
        state.document = null;
    }
    rl.closeAudioDevice();
    rl.closeWindow();
}














pub fn addLabel(id: []const u8, text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    const node = try state.dom.?.createElement("label");
    try state.dom.?.setAttribute(id, "id", id);
    try state.dom.?.setAttribute(id, "text", text);
    if (style) |s| try state.dom.?.setAttribute(id, "style", s);
    try state.dom.?.appendChild("window", node);
}

pub fn addButton(id: []const u8, text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    var node = try state.dom.?.createElement("button");
    try state.dom.?.setAttribute(id, "id", id);
    if (style) |s| try state.dom.?.setAttribute(id, "style", s);
    const text_node = try state.dom.?.createTextNode(text);
    try node.appendChild(text_node);
    try state.dom.?.appendChild("window", node);
}

pub fn addText(text: []const u8, style: ?[]const u8) !void {
    if (state.dom == null) return error.NoDom;
    var node = try state.dom.?.createTextNode(text);
    if (style) |s| try node.setAttribute("style", s);
    try state.dom.?.appendChild("window", node);
}

pub fn updateElementText(id: []const u8, new_text: []const u8) !void {
    if (state.dom == null) return error.NoDom;
    try state.dom.?.setTextContent(id, new_text);
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
    return state.dom.?.getTextContent(id);
}
