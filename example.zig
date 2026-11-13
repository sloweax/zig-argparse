const std = @import("std");
const argparse = @import("argparse.zig");
const Option = argparse.Option;

pub const Example = struct {
    flag: bool = false,
    str: []const u8 = "",
    num: i32 = 0,
    ip: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) },
    ignored: i32 = 0,

    pub const OptionMeta = struct {
        pub const ip = Option.positional.withDefaults("ip").withRequired(false);
        pub const flag = Option.flag.withDefaults("flag");
        pub const ignored = Option.ignored;
        // other fields are equivalent to Option.optional.withDefaults(field_name);
    };

    pub const OptionMetaFn = struct {
        pub fn ip(_: *argparse.Parser(Example), dst: *std.Io.net.IpAddress, src: []const u8) !void {
            dst.* = try std.Io.net.IpAddress.parse(src, 0);
        }
    };
};

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    var stderr = std.Io.File.stderr().writer(init.io, &.{});

    var it = init.minimal.args.iterate();

    var ex: Example = .{};
    var parser: argparse.Parser(Example) = .init(.{
        .name = it.next(),
        .stdout = &stdout.interface,
        .stderr = &stderr.interface,
    });
    try parser.parse(&it, &ex);

    std.debug.print("flag: {}\n", .{ex.flag});
    std.debug.print("str: {s}\n", .{ex.str});
    std.debug.print("num: {}\n", .{ex.num});
    std.debug.print("ip: {f}\n", .{ex.ip});
}
