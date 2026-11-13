const std = @import("std");
const argparse = @import("argparse.zig");
const Option = argparse.Option;

pub const Example = struct {
    help: bool = false,
    quiet: bool = false,
    opt: []const u8 = "",
    arg: []const u8 = "",

    pub const OptionMeta = struct {
        pub const help = Option.flag.withDefaults("help").withStop(true).withDescription("shows this message and exit");
        pub const quiet = Option.flag.withDefaults("quiet").withDescription("this is a flag");
        pub const opt = Option.optional.withDefaults("opt").withDescription("this is an optional");
        pub const arg = Option.positional.withDefaults("arg").withDescription("this is an argument").withRequired(false);
    };

    pub const OptionMetaFn = struct {
        pub fn help(parser: *argparse.Parser(Example), dst: *bool) !void {
            dst.* = true;
            try parser.usage(parser.o.stdout.?, null);
            try parser.o.stdout.?.writeByte('\n');
            try parser.help(parser.o.stdout.?);
            try parser.o.stdout.?.flush();
        }
    };
};

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var stderr = std.Io.File.stderr().writer(init.io, &.{});

    var it = init.minimal.args.iterate();

    var ex: Example = .{};
    var parser: argparse.Parser(@TypeOf(ex)) = .init(.{
        .name = it.next(),
        .stderr = &stderr.interface,
        .stdout = &stdout.interface,
    });

    try parser.parse(&it, &ex);
    if (ex.help) return;
    try stdout.interface.print("opt: {s}\n", .{ex.opt});
    try stdout.interface.print("arg: {s}\n", .{ex.arg});
    try stdout.interface.flush();
}
