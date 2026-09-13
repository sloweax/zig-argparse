pub fn parseInt(p: *Parser, comptime T: type, dst: *T, src: []const u8) !void {
    _ = p;
    dst.* = try std.fmt.parseInt(T, src, 10);
}

pub fn parseFloat(p: *Parser, comptime T: type, dst: *T, src: []const u8) !void {
    _ = p;
    dst.* = try std.fmt.parseFloat(T, src);
}

pub fn parseConstString(p: *Parser, dst: *[]const u8, src: []const u8) !void {
    _ = p;
    dst.* = src;
}

pub fn parseString(p: *Parser, dst: *[]u8, src: []const u8) !void {
    dst.* = try p.o.a.?.dupe(u8, src);
}

pub const Option = struct {
    name: ?[]const u8 = null,
    short: ?u8 = null,
    description: ?[]const u8 = null,
    type: enum {
        flag,
        optional,
        positional,
        ignored,
        // TODO: subcommand
    } = .optional,

    /// stops parsing after hitting this option
    stop: bool = false,

    /// used internally
    idx: usize = 0,

    pub fn fromName(name: []const u8) Option {
        std.debug.assert(name.len > 0);
        return .{
            .name = if (name.len == 1) null else name,
            .short = name[0],
        };
    }
};

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

        comptime var opt_buf = std.mem.zeroes([ti.@"struct".fields.len]Option);

        inline for (ti.@"struct".fields, 0..) |f, i| {
            const o: Option = comptime blk: {
                if (!@hasDecl(@TypeOf(st.*), "OptionMeta")) break :blk .fromName(f.name);
                if (!@hasField(@TypeOf(st.*).OptionMeta, f.name)) break :blk .fromName(f.name);
                for (@typeInfo(@TypeOf(st.*).OptionMeta).@"struct".fields) |f2| {
                    if (std.mem.eql(u8, f.name, f2.name)) break :blk f2.defaultValue() orelse .fromName(f.name);
                }
                break :blk .fromName(f.name);
            };
            opt_buf[i] = o;
            opt_buf[i].idx = i;
        }

        for (opt_buf) |a| {
            std.debug.assert((a.name != null or a.short != null) or a.type == .ignored);
        }

        comptime std.sort.block(Option, &opt_buf, {}, struct {
            pub fn lessfn(_: void, a1: Option, a2: Option) bool {
                if (a1.type == a2.type) return a1.idx < a2.idx;
                return @intFromEnum(a1.type) < @intFromEnum(a2.type);
            }
        }.lessfn);

        const flags: []Option = comptime blk: {
            var i: usize = 0;
            for (opt_buf) |a| {
                if (a.type != .flag) break;
                i += 1;
            }
            break :blk opt_buf[0..i];
        };

        const optionals: []Option = comptime blk: {
            var i: usize = flags.len;
            for (opt_buf[flags.len..]) |a| {
                if (a.type != .optional) break;
                i += 1;
            }
            break :blk opt_buf[flags.len..i];
        };

        var positional_idx: usize = 0;

        const positionals: []Option = comptime blk: {
            var i: usize = flags.len + optionals.len;
            for (opt_buf[flags.len + optionals.len ..]) |a| {
                if (a.type != .positional) break;
                i += 1;
            }
            break :blk opt_buf[flags.len + optionals.len .. i];
        };

        next: while (it.next()) |s| {
            if (s.len >= 2 and s[0] == '-' and s[1] != '-') {
                // '-f+' OR '-f+o' 'ANY' OR '-f+o' OR '-f+oANY'

                next_dash: for (s[1..], 0..) |c, i| {
                    inline for (flags) |o| {
                        if (o.short == c) {
                            try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), null);
                            if (o.stop) return else continue :next_dash;
                        }
                    }

                    inline for (optionals) |o| {
                        if (o.short == c) {
                            if (i == s.len - 2) {
                                if (it.next()) |next| {
                                    try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), next);
                                } else {
                                    // std.log.err("option -{c} requires an argument", .{o.short.?});
                                    return error.MissingArgument;
                                }
                            } else {
                                try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), s[1..][i + 1 ..]);
                            }
                            if (o.stop) return else continue :next;
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
                        if (std.mem.eql(u8, o.name orelse continue, key[2..])) {
                            try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), s[key.len + 1 ..]);
                            if (o.stop) return else continue :next;
                        }
                    }
                } else {
                    inline for (flags) |o| {
                        if (std.mem.eql(u8, o.name orelse continue, s[2..])) {
                            try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), null);
                            if (o.stop) return else continue :next;
                        }
                    }

                    inline for (optionals) |o| {
                        if (std.mem.eql(u8, o.name orelse continue, s[2..])) {
                            if (it.next()) |next| {
                                try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), next);
                                if (o.stop) return else continue :next;
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
                            try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), next);
                            positional_idx += 1;
                            if (o.stop) return else continue :next;
                        } else {
                            // std.log.err("option {s} requires an argument", .{s});
                            return error.MissingArgument;
                        }
                    } else {
                        try parse_field(self, st, ti.@"struct".fields[o.idx], o, &@field(st, ti.@"struct".fields[o.idx].name), s);
                        positional_idx += 1;
                        if (o.stop) return else continue :next;
                    }
                }
            }

            // std.log.err("unknown argument {s}", .{s});
            return error.UnknownArgument;
        }
    }

    fn parse_field(self: *Parser, st: anytype, comptime field: std.builtin.Type.StructField, comptime opt: Option, dst: anytype, src: ?[]const u8) !void {
        if (@hasDecl(@TypeOf(st.*), "OptionMetaFn")) {
            if (@hasDecl(@TypeOf(st.*).OptionMetaFn, field.name)) {
                return switch (opt.type) {
                    .flag => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, field.name), .{ self, dst }),
                    else => @call(.auto, @field(@TypeOf(st.*).OptionMetaFn, field.name), .{ self, dst, src.? }),
                };
            }
        }

        switch (@typeInfo(@TypeOf(dst.*))) {
            .int => |i| {
                return parseInt(self, @Int(i.signedness, i.bits), dst, src.?);
            },
            .float => {
                return parseFloat(self, @TypeOf(dst.*), dst, src.?);
            },
            else => {},
        }

        switch (@TypeOf(dst.*)) {
            bool => {
                if (opt.type == .flag) {
                    dst.* = true;
                    return;
                }
            },
            []const u8 => return parseConstString(self, dst, src.?),
            []u8 => return parseString(self, dst, src.?),
            else => {},
        }
        @compileError("Unsupported type");
    }
};

const std = @import("std");
