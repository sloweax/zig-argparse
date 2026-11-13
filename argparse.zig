pub const Option = struct {
    name: ?[]const u8 = null,
    short: ?u8 = null,
    metavar: ?[]const u8 = null,
    description: ?[]const u8 = null,
    required: bool = false,
    type: Type = .optional,

    /// stops parsing after hitting this option
    stop: bool = false,

    pub const flag: Option = .{ .type = .flag };
    pub const optional: Option = .{ .type = .optional };
    pub const positional: Option = .{ .type = .positional, .required = true };
    pub const command: Option = .{ .type = .command, .required = true };
    pub const ignored: Option = .{ .type = .ignored };

    pub const Type = enum {
        flag,
        optional,
        positional,
        command,
        ignored,
    };

    pub fn format(self: Option, w: *std.Io.Writer) !void {
        switch (self.type) {
            .flag, .optional => {
                if (self.short) |s| {
                    try w.writeByte('-');
                    try w.writeByte(s);
                } else {
                    try w.writeAll("--");
                    try w.writeAll(self.name.?);
                }
            },
            .command, .positional => try w.writeAll(self.name.?),
            .ignored => return,
        }
    }

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

    pub fn withDescription(o: Option, d: []const u8) Option {
        var new = o;
        new.description = d;
        return new;
    }

    pub fn withRequired(o: Option, v: bool) Option {
        var new = o;
        new.required = v;
        return new;
    }

    pub fn withStop(o: Option, v: bool) Option {
        var new = o;
        new.stop = v;
        return new;
    }
};

const OptionField = struct { o: Option, f: [:0]const u8, i: usize };

pub fn Parser(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            /// only used as convenience in some parser functions
            a: ?std.mem.Allocator = null,
            name: ?[]const u8 = null,
            stderr: ?*std.Io.Writer = null,
            stdout: ?*std.Io.Writer = null,
        };
        o: Options,

        pub fn init(opt: Options) Self {
            return .{ .o = opt };
        }

        pub fn defaultParseFlag(_: *Self, dst: anytype) !void {
            const TT = switch (@typeInfo(@TypeOf(dst.*))) {
                .optional => |o| o.child,
                else => @TypeOf(dst.*),
            };

            switch (TT) {
                bool => {
                    dst.* = true;
                    return;
                },
                else => {},
            }

            @compileError("Unsupported type");
        }

        pub fn defaultParse(p: *Self, dst: anytype, src: []const u8) !void {
            const TT = switch (@typeInfo(@TypeOf(dst.*))) {
                .optional => |o| o.child,
                else => @TypeOf(dst.*),
            };
            const TI = @typeInfo(TT);

            switch (TI) {
                .int => |i| {
                    dst.* = std.fmt.parseInt(@Int(i.signedness, i.bits), src, 10) catch |err| {
                        if (p.o.stderr) |w| {
                            try w.print("{s} is not a valid integer\n", .{src});
                            try w.flush();
                        }
                        return err;
                    };
                    return;
                },
                .float => {
                    dst.* = std.fmt.parseFloat(TT, src) catch |err| {
                        if (p.o.stderr) |w| {
                            try w.print("{s} is not a valid float\n", .{src});
                            try w.flush();
                        }
                        return err;
                    };
                    return;
                },
                else => {},
            }

            switch (TT) {
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
        pub fn options() [@typeInfo(T).@"struct".field_types.len]Option {
            const ti = comptime @typeInfo(T);
            comptime var opt_buf: [ti.@"struct".field_types.len]Option = undefined;

            inline for (ti.@"struct".field_names, 0..) |name, i| {
                const o: Option = comptime blk: {
                    if (!@hasDecl(T, "OptionMeta")) break :blk Option.optional.withDefaults(name);
                    if (!@hasDecl(T.OptionMeta, name)) break :blk Option.optional.withDefaults(name);
                    break :blk @field(T.OptionMeta, name);
                };
                opt_buf[i] = o;
            }

            return opt_buf;
        }

        fn optionsOfType(comptime t: Option.Type) [countOptionOfType(t)]Option {
            var i: usize = 0;
            var opts: [countOptionOfType(t)]Option = undefined;
            if (opts.len == 0) return opts;
            for (options()) |o| {
                if (o.type != t) continue;
                opts[i] = o;
                i += 1;
            }
            return opts;
        }

        fn countOptionOfType(comptime t: Option.Type) usize {
            var s = 0;
            for (options()) |o| {
                if (o.type == t) s += 1;
            }
            return s;
        }

        pub fn help(self: *Self, w: *std.Io.Writer) !void {
            _ = self;
            var buf: [4096]u8 = undefined;
            var max: usize = 0;
            var arr = std.ArrayList(u8).initBuffer(&buf);
            const pad = 4;
            for (options()) |o| {
                var cur: usize = 0;
                switch (o.type) {
                    .optional, .flag => {
                        if (o.short != null) {
                            cur += 2;
                        }
                        if (o.name) |n| {
                            if (cur != 0) cur += 2;
                            cur += n.len + 2;
                        }
                        if (o.metavar) |m| {
                            cur += m.len + 1;
                        }
                    },
                    .command, .positional => {
                        cur += o.name.?.len;
                    },
                    .ignored => continue,
                }
                max = @max(cur, max);
            }

            for (optionsOfType(.flag) ++ optionsOfType(.optional)) |o| {
                for (0..pad) |_| try w.writeByte(' ');
                if (o.short) |s| {
                    try arr.appendBounded('-');
                    try arr.appendBounded(s);
                }
                if (o.name) |n| {
                    if (arr.items.len != 0) try arr.appendSliceBounded(", ");
                    try arr.appendSliceBounded("--");
                    try arr.appendSliceBounded(n);
                }
                if (o.metavar) |m| {
                    try arr.appendBounded(' ');
                    try arr.appendSliceBounded(m);
                }
                try w.writeAll(arr.items);
                if (o.description) |d| {
                    try printDescription(w, pad + arr.items.len, max + pad * 2, d);
                }
                try w.writeByte('\n');
                arr.clearRetainingCapacity();
            }

            for (optionsOfType(.positional) ++ optionsOfType(.command)) |o| {
                for (0..pad) |_| try w.writeByte(' ');
                try w.writeAll(o.name.?);
                if (o.description) |d| {
                    try printDescription(w, pad + o.name.?.len, max + pad * 2, d);
                }
                try w.writeByte('\n');
            }
        }

        pub fn usage(self: *Self, w: *std.Io.Writer, prefix: ?[]const u8) !void {
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

            next: for (optionsOfType(.flag)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');

                    if (!o.required) try arr.appendBounded('[');
                    if (o.short) |s| {
                        try arr.appendBounded('-');
                        try arr.appendBounded(s);
                    } else {
                        try arr.appendSliceBounded("--");
                        try arr.appendSliceBounded(o.name.?);
                    }
                    if (!o.required) try arr.appendBounded(']');

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

            next: for (optionsOfType(.optional)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');

                    if (!o.required) try arr.appendBounded('[');
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
                    if (!o.required) try arr.appendBounded(']');

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

            next: for (optionsOfType(.positional)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');

                    if (!o.required) try arr.appendBounded('[');
                    try arr.appendSliceBounded(o.name.?);
                    if (!o.required) try arr.appendBounded(']');

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

            next: for (optionsOfType(.command)) |o| {
                while (true) {
                    while (cur < pad) {
                        try w.writeByte(' ');
                        cur += 1;
                    }
                    if (cur != pad) try arr.appendBounded(' ');

                    if (!o.required) try arr.appendBounded('[');
                    try arr.appendSliceBounded(o.name.?);
                    if (!o.required) try arr.appendBounded(']');

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

        pub fn parse(self: *Self, it: *std.process.Args.Iterator, st: anytype) !void {
            const ti = comptime @typeInfo(@TypeOf(st.*));

            switch (ti) {
                .@"struct" => {},
                else => {
                    @compileError("Only structs are supported");
                },
            }

            const opts = comptime options();
            comptime var optsf: [opts.len]OptionField = undefined;
            var required_check: [opts.len]bool = undefined;
            inline for (opts, 0..) |o, i| {
                optsf[i] = .{ .o = o, .i = i, .f = ti.@"struct".field_names[i] };
                required_check[i] = o.required;
            }

            comptime std.sort.block(OptionField, &optsf, {}, struct {
                pub fn lessfn(_: void, o1: OptionField, o2: OptionField) bool {
                    if (o1.o.type == o2.o.type) return o1.i < o2.i;
                    return @backingInt(o1.o.type) < @backingInt(o2.o.type);
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
                                try parseField(self, st, o, &@field(st, o.f), null);
                                required_check[o.i] = false;
                                if (o.o.stop) return else continue :next_dash;
                            }
                        }

                        inline for (optionals) |o| {
                            if (o.o.short == c) {
                                if (i == s.len - 2) {
                                    if (it.next()) |next| {
                                        try parseField(self, st, o, &@field(st, o.f), next);
                                        required_check[o.i] = false;
                                    } else {
                                        if (self.o.stderr) |w| {
                                            try w.print("option -{c} requires an argument\n", .{c});
                                            try w.flush();
                                        }
                                        return error.MissingArgument;
                                    }
                                } else {
                                    try parseField(self, st, o, &@field(st, o.f), s[1..][i + 1 ..]);
                                    required_check[o.i] = false;
                                }
                                if (o.o.stop) return else continue :next;
                            }
                        }
                        if (self.o.stderr) |w| {
                            try w.print("unknown option -{c}\n", .{c});
                            try w.flush();
                        }
                        return error.UnknownOption;
                    }

                    continue :next;
                }

                if (s.len >= 3 and s[0] == '-' and s[1] == '-' and s[2] != '-') {
                    // '--opt' OR '--opt' 'ANY' OR '--opt=ANY' OR '--flag'

                    if (std.mem.containsAtLeastScalar(u8, s, '=', 1)) {
                        var tmp = std.mem.splitScalar(u8, s, '=');
                        const key = tmp.next().?;
                        inline for (optionals) |o| {
                            if (std.mem.eql(u8, o.o.name orelse continue, key[2..])) {
                                try parseField(self, st, o, &@field(st, o.f), s[key.len + 1 ..]);
                                required_check[o.i] = false;
                                if (o.o.stop) return else continue :next;
                            }
                        }

                        if (self.o.stderr) |w| {
                            try w.print("unknown option {s}\n", .{key});
                            try w.flush();
                        }
                        return error.UnknownOption;
                    } else {
                        inline for (flags) |o| {
                            if (std.mem.eql(u8, o.o.name orelse continue, s[2..])) {
                                try parseField(self, st, o, &@field(st, o.f), null);
                                required_check[o.i] = false;
                                if (o.o.stop) return else continue :next;
                            }
                        }

                        inline for (optionals) |o| {
                            if (std.mem.eql(u8, o.o.name orelse continue, s[2..])) {
                                if (it.next()) |next| {
                                    try parseField(self, st, o, &@field(st, o.f), next);
                                    required_check[o.i] = false;
                                    if (o.o.stop) return else continue :next;
                                } else {
                                    if (self.o.stderr) |w| {
                                        try w.print("option {s} requires an argument\n", .{s});
                                        try w.flush();
                                    }
                                    return error.MissingArgument;
                                }
                            }
                        }
                    }

                    if (self.o.stderr) |w| {
                        try w.print("unknown option {s}\n", .{s});
                        try w.flush();
                    }
                    return error.UnknownOption;
                }

                // 'ANY' OR '--' 'ANY'
                inline for (positionals, 0..) |o, i| {
                    if (i == positional_idx) {
                        if (std.mem.eql(u8, "--", s)) {
                            if (it.next()) |next| {
                                try parseField(self, st, o, &@field(st, o.f), next);
                                required_check[o.i] = false;
                                positional_idx += 1;
                                if (o.o.stop) return else continue :next;
                            } else {
                                if (self.o.stderr) |w| {
                                    try w.print("option {f} requires an argument\n", .{o.o});
                                    try w.flush();
                                }
                                return error.MissingArgument;
                            }
                        } else {
                            try parseField(self, st, o, &@field(st, o.f), s);
                            required_check[o.i] = false;
                            positional_idx += 1;
                            if (o.o.stop) return else continue :next;
                        }
                    }
                }

                inline for (commands) |o| {
                    const u = @field(st, o.f);
                    const ui = @typeInfo(@TypeOf(u));
                    const uci = @typeInfo(ui.optional.child);
                    inline for (uci.@"union".field_names) |f| {
                        if (std.mem.eql(u8, s, f)) {
                            @field(st, o.f) = @unionInit(ui.optional.child, f, .{});
                            required_check[o.i] = false;
                            if (o.o.stop) return;
                            for (required_check, 0..) |c, i| {
                                if (!c) continue;
                                if (self.o.stderr) |w| {
                                    try w.print("option {f} is required\n", .{opts[i]});
                                    try w.flush();
                                }
                                return error.MissingRequiredOption;
                            }
                            var tmp_parser: Parser(@TypeOf(@field(@field(st, o.f).?, f))) = .init(self.o);
                            return @call(.auto, @TypeOf(tmp_parser).parse, .{ &tmp_parser, it, &@field(@field(st, o.f).?, f) });
                        }
                    }
                }

                if (self.o.stderr) |w| {
                    try w.print("unknown argument {s}\n", .{s});
                    try w.flush();
                }
                return error.UnknownArgument;
            }

            for (required_check, 0..) |c, i| {
                if (!c) continue;
                if (self.o.stderr) |w| {
                    try w.print("option {f} is required\n", .{opts[i]});
                    try w.flush();
                }
                return error.MissingRequiredOption;
            }
        }

        fn parseField(self: *Self, st: anytype, comptime o: OptionField, dst: anytype, src: ?[]const u8) !void {
            if (@hasDecl(@TypeOf(st.*), "OptionMetaFn")) {
                if (@hasDecl(@TypeOf(st.*).OptionMetaFn, o.f)) {
                    return switch (o.o.type) {
                        .flag => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, o.f), .{ self, dst }),
                        else => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, o.f), .{ self, dst, src.? }),
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
}

fn printDescription(w: *std.Io.Writer, start: usize, pad: usize, m: []const u8) !void {
    var cur: usize = start;
    const max = 80;
    var it = std.mem.tokenizeAny(u8, m, " \n");
    next: while (it.next()) |s| {
        while (true) {
            var have_newline: bool = false;
            const str = blk: {
                if (it.peek() == null) break :blk s;
                // hacky way to check if it ends with newline
                var tmp = s;
                tmp.len += 1;
                if (tmp[tmp.len - 1] == '\n') have_newline = true;
                break :blk s;
            };

            while (cur < pad) {
                try w.writeByte(' ');
                cur += 1;
            }
            if (cur == pad and str.len + pad > max) {
                try w.writeAll(str);
                try w.writeByte('\n');
                cur = 0;
                continue :next;
            }
            if (cur + str.len > max) {
                cur = 0;
                try w.writeByte('\n');
                continue;
            }
            try w.writeAll(str);
            cur += str.len;
            if (have_newline) {
                cur = 0;
                try w.writeByte('\n');
                continue :next;
            }
            if (it.peek() != null) {
                if (cur + 1 > max) {
                    cur = 0;
                    try w.writeByte('\n');
                } else {
                    cur += 1;
                    try w.writeByte(' ');
                }
            }
            continue :next;
        }
    }
}

const std = @import("std");
