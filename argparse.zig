pub const Option = struct {
    name: ?[]const u8 = null,
    short: ?u8 = null,
    metavar: ?[]const u8 = null,
    description: ?[]const u8 = null,
    type: Type = .optional,

    /// stops parsing after hitting this option
    stop: bool = false,

    pub const flag: Option = .{ .type = .flag };
    pub const optional: Option = .{ .type = .optional };
    pub const positional: Option = .{ .type = .positional };
    pub const command: Option = .{ .type = .command };
    pub const ignored: Option = .{ .type = .ignored };

    pub const Type = enum {
        flag,
        optional,
        positional,
        command,
        ignored,
    };

    pub fn withDefaults(o: Option, name: []const u8) Option {
        var new = o;
        new.name = name;
        switch (new.type) {
            .flag, .optional => {
                if (name.len > 0) {
                    new.short = name[0];
                    if (name.len == 1)
                        new.name = null;
                }
                if (new.type == .optional)
                    new.metavar = name;
            },
            else => {},
        }
        return new;
    }

    pub fn withName(o: Option, name: []const u8) Option {
        var new = o;
        new.name = name;
        return new;
    }

    pub fn withMetavar(o: Option, m: []const u8) Option {
        var new = o;
        new.metavar = m;
        return new;
    }
};

const OptionField = struct { o: Option, f: std.builtin.Type.StructField, i: usize };

pub fn defaultParseFlag(_: *Parser, dst: anytype) !void {
    const T = switch (@typeInfo(@TypeOf(dst.*))) {
        .optional => |o| o.child,
        else => @TypeOf(dst.*),
    };

    switch (T) {
        bool => {
            dst.* = true;
            return;
        },
        else => {},
    }

    @compileError("Unsupported type");
}

pub fn defaultParse(p: *Parser, dst: anytype, src: []const u8) !void {
    const T = switch (@typeInfo(@TypeOf(dst.*))) {
        .optional => |o| o.child,
        else => @TypeOf(dst.*),
    };
    const TI = @typeInfo(T);

    switch (TI) {
        .int => |i| {
            dst.* = try std.fmt.parseInt(@Int(i.signedness, i.bits), src, 10);
            return;
        },
        .float => {
            dst.* = try std.fmt.parseFloat(T, src);
            return;
        },
        else => {},
    }

    switch (T) {
        []const u8 => {
            dst.* = src;
            return;
        },
        []u8 => {
            dst.* = try p.o.a.?.dupe(u8, src);
            return;
        },
        else => {},
    }

    @compileError("Unsupported type");
}

pub const Parser = struct {
    // TODO: add option to generate --help
    // TODO: add option to generate diagnostics

    pub const Options = struct {
        /// only used as convenience in some parser functions
        a: ?std.mem.Allocator = null,
        name: ?[]const u8 = null,
    };

    o: Options,

    pub fn init(opt: Options) Parser {
        return .{ .o = opt };
    }

    pub fn usage(self: *Parser, w: *std.Io.Writer, comptime T: type, prefix: ?[]const u8) !void {
        var buf: [4096]u8 = undefined;
        var arr = std.ArrayList(u8).initBuffer(&buf);

        const progname = self.o.name orelse "?";
        var pad = progname.len + 2 + 6;
        const max = 80;

        try w.print("usage: {s} ", .{progname});

        if (prefix) |p| {
            try w.print("{s} ", .{p});
            pad += p.len + 1;
        }

        var cur = pad;

        if (comptime countOptionOfType(T, .flag) > 0) {
            next: for (optionsOfType(T, .flag)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');
                    try arr.appendBounded('[');
                    if (o.short) |s| {
                        try arr.appendBounded('-');
                        try arr.appendBounded(s);
                    } else {
                        try arr.appendSliceBounded("--");
                        try arr.appendSliceBounded(o.name.?);
                    }
                    try arr.appendBounded(']');
                    if (cur == pad and arr.items.len + pad > max) {
                        cur = 0;
                        try w.writeAll(arr.items);
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue :next;
                    }
                    if (cur + arr.items.len > max) {
                        cur = 0;
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue;
                    }
                    try w.writeAll(arr.items);
                    cur += arr.items.len;
                    arr.clearRetainingCapacity();
                    continue :next;
                }
            }
        }

        if (comptime countOptionOfType(T, .optional) > 0) {
            next: for (optionsOfType(T, .optional)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');
                    try arr.appendBounded('[');
                    if (o.short) |s| {
                        try arr.appendBounded('-');
                        try arr.appendBounded(s);
                    } else {
                        try arr.appendSliceBounded("--");
                        try arr.appendSliceBounded(o.name.?);
                    }
                    if (o.metavar) |m| {
                        try arr.appendBounded(' ');
                        try arr.appendSliceBounded(m);
                    }
                    try arr.appendBounded(']');
                    if (cur == pad and arr.items.len + pad > max) {
                        cur = 0;
                        try w.writeAll(arr.items);
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue :next;
                    }
                    if (cur + arr.items.len > max) {
                        cur = 0;
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue;
                    }
                    try w.writeAll(arr.items);
                    cur += arr.items.len;
                    arr.clearRetainingCapacity();
                    continue :next;
                }
            }
        }

        if (comptime countOptionOfType(T, .positional) > 0) {
            next: for (optionsOfType(T, .positional)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');
                    try arr.appendBounded('[');
                    try arr.appendSliceBounded(o.name.?);
                    try arr.appendBounded(']');
                    if (cur == pad and arr.items.len + pad > max) {
                        cur = 0;
                        try w.writeAll(arr.items);
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue :next;
                    }
                    if (cur + arr.items.len > max) {
                        cur = 0;
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue;
                    }
                    try w.writeAll(arr.items);
                    cur += arr.items.len;
                    arr.clearRetainingCapacity();
                    continue :next;
                }
            }
        }

        if (comptime countOptionOfType(T, .command) > 0) {
            next: for (optionsOfType(T, .command)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');
                    try arr.appendSliceBounded(o.name.?);
                    if (cur == pad and arr.items.len + pad > max) {
                        cur = 0;
                        try w.writeAll(arr.items);
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue :next;
                    }
                    if (cur + arr.items.len > max) {
                        cur = 0;
                        try w.writeByte('\n');
                        arr.clearRetainingCapacity();
                        continue;
                    }
                    try w.writeAll(arr.items);
                    cur += arr.items.len;
                    arr.clearRetainingCapacity();
                    continue :next;
                }
            }
        }
    }

    pub fn options(comptime T: type) [@typeInfo(T).@"struct".fields.len]Option {
        const ti = comptime @typeInfo(T);
        comptime var opt_buf: [ti.@"struct".fields.len]Option = undefined;

        inline for (ti.@"struct".fields, 0..) |f, i| {
            const o: Option = comptime blk: {
                if (!@hasDecl(T, "OptionMeta")) break :blk Option.optional.withDefaults(f.name);
                if (!@hasDecl(T.OptionMeta, f.name)) break :blk Option.optional.withDefaults(f.name);
                break :blk @field(T.OptionMeta, f.name);
            };
            opt_buf[i] = o;
        }

        return opt_buf;
    }

    fn optionsOfType(comptime T: type, comptime t: Option.Type) [countOptionOfType(T, t)]Option {
        var i: usize = 0;
        var opts: [countOptionOfType(T, t)]Option = undefined;
        for (options(T)) |o| {
            if (o.type != t) continue;
            opts[i] = o;
            i += 1;
        }
        return opts;
    }

    fn countOptionOfType(comptime T: type, comptime t: Option.Type) usize {
        var s = 0;
        for (options(T)) |o| {
            if (o.type == t) s += 1;
        }
        return s;
    }

    pub fn parse(self: *Parser, it: *std.process.Args.Iterator, st: anytype) !void {
        const ti = comptime @typeInfo(@TypeOf(st.*));

        switch (ti) {
            .@"struct" => {},
            else => {
                @compileError("Only structs are supported");
            },
        }

        const opts = comptime options(@TypeOf(st.*));
        comptime var optsf: [opts.len]OptionField = undefined;
        inline for (opts, 0..) |o, i| {
            optsf[i] = .{ .o = o, .i = i, .f = ti.@"struct".fields[i] };
        }

        comptime std.sort.block(OptionField, &optsf, {}, struct {
            pub fn lessfn(_: void, o1: OptionField, o2: OptionField) bool {
                if (o1.o.type == o2.o.type) return o1.i < o2.i;
                return @intFromEnum(o1.o.type) < @intFromEnum(o2.o.type);
            }
        }.lessfn);

        inline for (opts) |o| {
            std.debug.assert((o.name != null or o.short != null) or o.type == .ignored);
        }

        const flags: []OptionField = comptime blk: {
            var i: usize = 0;
            for (optsf) |a| {
                if (a.o.type != .flag) break;
                i += 1;
            }
            break :blk optsf[0..i];
        };

        const optionals: []OptionField = comptime blk: {
            var i: usize = flags.len;
            for (optsf[flags.len..]) |a| {
                if (a.o.type != .optional) break;
                i += 1;
            }
            break :blk optsf[flags.len..i];
        };

        var positional_idx: usize = 0;

        const positionals: []OptionField = comptime blk: {
            var i: usize = flags.len + optionals.len;
            for (optsf[flags.len + optionals.len ..]) |a| {
                if (a.o.type != .positional) break;
                i += 1;
            }
            break :blk optsf[flags.len + optionals.len .. i];
        };

        inline for (positionals) |o| std.debug.assert(o.o.name != null);

        const commands: []OptionField = comptime blk: {
            var i: usize = flags.len + optionals.len + positionals.len;
            for (optsf[flags.len + optionals.len + positionals.len ..]) |a| {
                if (a.o.type != .command) break;
                i += 1;
            }
            break :blk optsf[flags.len + optionals.len + positionals.len .. i];
        };

        inline for (commands) |o| std.debug.assert(o.o.name != null);

        next: while (it.next()) |s| {
            if (s.len >= 2 and s[0] == '-' and s[1] != '-') {
                // '-f+' OR '-f+o' 'ANY' OR '-f+o' OR '-f+oANY'

                next_dash: for (s[1..], 0..) |c, i| {
                    inline for (flags) |o| {
                        if (o.o.short == c) {
                            try parseField(self, st, o, &@field(st, o.f.name), null);
                            if (o.o.stop) return else continue :next_dash;
                        }
                    }

                    inline for (optionals) |o| {
                        if (o.o.short == c) {
                            if (i == s.len - 2) {
                                if (it.next()) |next| {
                                    try parseField(self, st, o, &@field(st, o.f.name), next);
                                } else {
                                    // std.log.err("option -{c} requires an argument", .{o.short.?});
                                    return error.MissingArgument;
                                }
                            } else {
                                try parseField(self, st, o, &@field(st, o.f.name), s[1..][i + 1 ..]);
                            }
                            if (o.o.stop) return else continue :next;
                        }
                    }
                    // std.log.err("unknown option -{c}", .{c});
                    return error.UnknownOption;
                }

                continue :next;
            }

            if (s.len >= 3 and s[0] == '-' and s[1] == '-' and s[3] != '-') {
                // '--opt' OR '--opt' 'ANY' OR '--opt=ANY' OR '--flag'

                if (std.mem.containsAtLeastScalar(u8, s, 1, '=')) {
                    var tmp = std.mem.splitScalar(u8, s, '=');
                    const key = tmp.next().?;
                    inline for (optionals) |o| {
                        if (std.mem.eql(u8, o.o.name orelse continue, key[2..])) {
                            try parseField(self, st, o, &@field(st, o.f.name), s[key.len + 1 ..]);
                            if (o.o.stop) return else continue :next;
                        }
                    }
                } else {
                    inline for (flags) |o| {
                        if (std.mem.eql(u8, o.o.name orelse continue, s[2..])) {
                            try parseField(self, st, o, &@field(st, o.f.name), null);
                            if (o.o.stop) return else continue :next;
                        }
                    }

                    inline for (optionals) |o| {
                        if (std.mem.eql(u8, o.o.name orelse continue, s[2..])) {
                            if (it.next()) |next| {
                                try parseField(self, st, o, &@field(st, o.f.name), next);
                                if (o.o.stop) return else continue :next;
                            } else {
                                // std.log.err("option {s} requires an argument", .{s});
                                return error.MissingArgument;
                            }
                        }
                    }
                }

                // std.log.err("unknown option {s}", .{s});
                return error.UnknownOption;
            }

            // 'ANY' OR '--' 'ANY'
            inline for (positionals, 0..) |o, i| {
                if (i == positional_idx) {
                    if (std.mem.eql(u8, "--", s)) {
                        if (it.next()) |next| {
                            try parseField(self, st, o, &@field(st, o.f.name), next);
                            positional_idx += 1;
                            if (o.o.stop) return else continue :next;
                        } else {
                            // std.log.err("option {s} requires an argument", .{s});
                            return error.MissingArgument;
                        }
                    } else {
                        try parseField(self, st, o, &@field(st, o.f.name), s);
                        positional_idx += 1;
                        if (o.o.stop) return else continue :next;
                    }
                }
            }

            inline for (commands) |o| {
                const u = @field(st, o.f.name);
                const ui = @typeInfo(@TypeOf(u));
                const uci = @typeInfo(ui.optional.child);
                inline for (uci.@"union".fields) |f| {
                    if (std.mem.eql(u8, s, f.name)) {
                        @field(st, o.f.name) = @unionInit(ui.optional.child, f.name, .{});
                        if (o.o.stop) return;
                        return @call(.auto, Parser.parse, .{ self, it, &@field(@field(st, o.f.name).?, f.name) });
                    }
                }
            }

            // std.log.err("unknown argument {s}", .{s});
            return error.UnknownArgument;
        }
    }

    fn parseField(self: *Parser, st: anytype, comptime o: OptionField, dst: anytype, src: ?[]const u8) !void {
        if (@hasDecl(@TypeOf(st.*), "OptionMetaFn")) {
            if (@hasDecl(@TypeOf(st.*).OptionMetaFn, o.f.name)) {
                return switch (o.o.type) {
                    .flag => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, o.f.name), .{ self, dst }),
                    else => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, o.f.name), .{ self, dst, src.? }),
                };
            }
        }

        return switch (o.o.type) {
            .flag => defaultParseFlag(self, dst),
            .optional, .positional => defaultParse(self, dst, src.?),
            .command, .ignored => @compileError("Unsupported type"),
        };
    }
};

const std = @import("std");
