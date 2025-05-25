const std = @import("std");
const exsw = @import("EXSW");
const rl = exsw.rl;

fn createNode(name: ?[]const u8, text: ?[]const u8) *exsw.xml.Node {
    if (name == null) {
        return exsw.xml.Node.init(std.heap.page_allocator, .Text, name, text) catch @panic("could not create node");
    } else {
        return exsw.xml.Node.init(std.heap.page_allocator, .Element, name, text) catch @panic("could not create node");
    }
}

var counter: u32 = 0;

fn handleClick(payload: exsw.WindowEvent) void {
    std.debug.print("{s} {any}\n", .{payload.id, payload.type});
}

pub fn main() !u8 {
    exsw.initEXSW(1600, 800);
    rl.setTargetFPS(60);
    try exsw.renderFile("example.xasf");
    try exsw.windowEvents.addListener(.BUTTON_CLICK, handleClick);
    try exsw.windowEvents.addListener(.CHECKBOX_CHECKED, handleClick);

    while (!rl.windowShouldClose()) {
        exsw.renderDocument();
    }    
    exsw.closeEXSW();
    return 0;
}
