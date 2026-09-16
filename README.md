# Example

```zig
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
        pub const ip = Option.positional.withDefaults("ip");
        pub const flag = Option.flag.withDefaults("flag");
        pub const ignored = Option.ignored;
        // other fields are equivalent to Option.optional.withDefaults(field_name);
    };

    pub const OptionMetaFn = struct {
        pub fn ip(_: *argparse.Parser, dst: *std.Io.net.IpAddress, src: []const u8) !void {
            dst.* = try std.Io.net.IpAddress.parse(src, 0);
        }
    };
};

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();
    // consume progname
    _ = it.next();

    var ex: Example = .{};
    var parser = argparse.Parser.init(.{});
    try parser.parse(&it, &ex);

    std.debug.print("flag: {}\n", .{ex.flag});
    std.debug.print("str: {s}\n", .{ex.str});
    std.debug.print("num: {}\n", .{ex.num});
    std.debug.print("ip: {f}\n", .{ex.ip});
}
```

```sh
./example --num 32 -f  1.2.3.4 --str=abc 
# flag: true
# str: abc
# num: 32
# ip: 1.2.3.4:0

./example -fn 999 -s foo 
# flag: true
# str: foo
# num: 999
# ip: 127.0.0.1:0
```

# Command example

```zig
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
        pub const cmd = Option.command.withDefaults("cmd");
        pub const num = Option.positional.withDefaults("num");
    };

    pub const Cmd1 = struct {
        num: i32 = 0,

        pub const OptionMeta = struct {
            pub const num = Option.positional.withDefaults("num");
        };
    };

    pub const Cmd2 = struct {
        num: i32 = 0,

        pub const OptionMeta = struct {
            pub const num = Option.positional.withDefaults("num");
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
```

```sh
./command 123 cmd1 321
# num: 123
# num.cmd1: 321

./command 111 cmd2 999
# num: 111
# num.cmd2: 999
```

# Usage and help example

```zig
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
```

```sh
./help-usage 
# usage: ./help-usage [-q] [-o opt] [arg] cmd
#     -q, --quiet      this is a flag
#     -o, --opt opt    this is an optional
#     arg              this is an argument
#     cmd              this is a command
```
