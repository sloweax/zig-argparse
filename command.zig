const std = @import("std");
const argparse = @import("argparse.zig");
const Option = argparse.Option;

pub const Example = struct {
    num: i32 = 0,
    cmd: ?union(enum) {
        cmd1: Cmd1,
        cmd2: Cmd2,
    } = null,

    pub const OptionMeta = struct {
        pub const cmd = Option.command.withName("cmd");
        pub const num = Option.positional.withName("num");
    };

    pub const Cmd1 = struct {
        num: i32 = 0,

        pub const OptionMeta = struct {
            pub const num = Option.positional.withName("num");
        };
    };

    pub const Cmd2 = struct {
        num: i32 = 0,

        pub const OptionMeta = struct {
            pub const num = Option.positional.withName("num");
        };
    };
};

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();
    // consume progname
    _ = it.next();

    var ex: Example = .{};
    var parser = argparse.Parser.init(.{});
    try parser.parse(&it, &ex);

    std.debug.print("num: {}\n", .{ex.num});

    if (ex.cmd) |cmd| switch (cmd) {
        .cmd1 => |c| std.debug.print("num.cmd1: {}\n", .{c.num}),
        .cmd2 => |c| std.debug.print("num.cmd2: {}\n", .{c.num}),
    };
}
