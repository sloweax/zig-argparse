const std = @import("std");
const argparse = @import("argparse.zig");
const Option = argparse.Option;

pub const Example = struct {
    quiet: bool = false,
    opt: []const u8 = "",
    arg: []const u8 = "",
    cmd: ?union(enum) {
        cmd1: Command1,
    } = null,

    pub const Command1 = struct {
        ignored: i32 = 0,
    };

    pub const OptionMeta = struct {
        pub const quiet = Option.flag.withDefaults("quiet").withDescription("this is a flag");
        pub const opt = Option.optional.withDefaults("opt").withDescription("this is an optional");
        pub const arg = Option.positional.withDefaults("arg").withDescription("this is an argument");
        pub const cmd = Option.command.withDefaults("cmd").withDescription("this is a command");
    };
};

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();

    var ex: Example = .{};
    var parser = argparse.Parser.init(.{
        .name = it.next(),
    });
    try parser.parse(&it, &ex);

    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try parser.usage(&stdout.interface, @TypeOf(ex), null);
    try stdout.interface.writeByte('\n');
    try parser.help(&stdout.interface, @TypeOf(ex));
    try stdout.flush();
}
