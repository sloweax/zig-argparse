pub const Option = struct {
    name: ?[]const u8 = null,
    short: ?u8 = null,
    description: ?[]const u8 = null,
    type: enum {
        flag,
        optional,
        positional,
        command,
        ignored,
    } = .optional,

    /// stops parsing after hitting this option
    stop: bool = false,

    pub const flag: Option = .{ .type = .flag };
    pub const optional: Option = .{ .type = .optional };
    pub const positional: Option = .{ .type = .positional };
    pub const command: Option = .{ .type = .command };
    pub const ignored: Option = .{ .type = .ignored };

    pub fn withName(o: Option, name: []const u8) Option {
        var new = o;
        if (name.len == 0) {
            new.name = null;
            new.short = null;
        } else {
            new.short = name[0];
            new.name = if (name.len == 1) null else name;
        }
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
    // TODO: add option to generate usage and --help
    // TODO: add option to generate diagnostics

    pub const Options = struct {
        /// only used as convenience in some parser functions
        a: ?std.mem.Allocator = null,
    };

    o: Options,

    pub fn init(opt: Options) Parser {
        return .{ .o = opt };
    }

    pub fn parse(self: *Parser, it: *std.process.Args.Iterator, st: anytype) !void {
        const ti = comptime @typeInfo(@TypeOf(st.*));

        switch (ti) {
            .@"struct" => {},
            else => {
                @compileError("Only structs are supported");
            },
        }

        comptime var opt_buf: [ti.@"struct".fields.len]OptionField = undefined;

        inline for (ti.@"struct".fields, 0..) |f, i| {
            const o: Option = comptime blk: {
                if (!@hasDecl(@TypeOf(st.*), "OptionMeta")) break :blk Option.optional.withName(f.name);
                if (!@hasDecl(@TypeOf(st.*).OptionMeta, f.name)) break :blk Option.optional.withName(f.name);
                break :blk @field(@TypeOf(st.*).OptionMeta, f.name);
            };
            opt_buf[i] = .{ .o = o, .f = f, .i = i };
        }

        inline for (opt_buf) |o| {
            std.debug.assert((o.o.name != null or o.o.short != null) or o.o.type == .ignored);
        }

        comptime std.sort.block(OptionField, &opt_buf, {}, struct {
            pub fn lessfn(_: void, o1: OptionField, o2: OptionField) bool {
                if (o1.o.type == o2.o.type) return o1.i < o2.i;
                return @intFromEnum(o1.o.type) < @intFromEnum(o2.o.type);
            }
        }.lessfn);

        const flags: []OptionField = comptime blk: {
            var i: usize = 0;
            for (opt_buf) |a| {
                if (a.o.type != .flag) break;
                i += 1;
            }
            break :blk opt_buf[0..i];
        };

        const optionals: []OptionField = comptime blk: {
            var i: usize = flags.len;
            for (opt_buf[flags.len..]) |a| {
                if (a.o.type != .optional) break;
                i += 1;
            }
            break :blk opt_buf[flags.len..i];
        };

        var positional_idx: usize = 0;

        const positionals: []OptionField = comptime blk: {
            var i: usize = flags.len + optionals.len;
            for (opt_buf[flags.len + optionals.len ..]) |a| {
                if (a.o.type != .positional) break;
                i += 1;
            }
            break :blk opt_buf[flags.len + optionals.len .. i];
        };

        const commands: []OptionField = comptime blk: {
            var i: usize = flags.len + optionals.len + positionals.len;
            for (opt_buf[flags.len + optionals.len + positionals.len ..]) |a| {
                if (a.o.type != .command) break;
                i += 1;
            }
            break :blk opt_buf[flags.len + optionals.len + positionals.len .. i];
        };

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
