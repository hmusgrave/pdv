const std = @import("std");
const testing = std.testing;

fn naive_memoize(comptime _: anytype) type {
    return opaque {};
}

test "structural equality sanity check" {
    // If we're going to canonicalize types by relying on a memoized wrapper type then
    // we should ensure the memoization actually does what we expect. I recall a discussion
    // about exactly how memoization should work for arrays, strings, and whatnot, so this
    // test should probably stick around at least till Zig-1.0. If it fails, the rest
    // of the library is probably broken for most uses.

    // a couple unique types for setup
    const a = opaque {};
    const b = opaque {};

    // ensure we're working with different types
    try testing.expect(a != b);

    // ensure that memoization yields different types
    try testing.expect(naive_memoize(a) != naive_memoize(b));

    // ensure the call is actually memoized
    try testing.expectEqual(naive_memoize(a), naive_memoize(a));

    // test for structural equality
    const c: [2]type = .{ a, b };
    const d: [2]type = .{ a, b };
    try testing.expectEqual(naive_memoize(c), naive_memoize(d));

    // sanity check that structural equality can return false
    const e: [2]type = .{ a, a };
    try testing.expect(naive_memoize(c) != naive_memoize(e));
}

// TODO: kind of hacky and prone to misuse?
fn type_id_gen(comptime _: anytype) type {
    comptime var count: usize = 0;
    return struct {
        pub fn idx(comptime T: anytype) usize {
            _ = T;
            defer count += 1;
            return count;
        }
    };
}

fn type_lt(comptime lhs: anytype, comptime rhs: anytype) bool {
    comptime var id_gen = type_id_gen(0);
    return id_gen.idx(lhs) < id_gen.idx(rhs);
}

// TODO: sorting and comptime slices of types don't play well in the stdlib.
// - can't sort the slice because some comptime issue is messing with the
//   memory layout and cloning rather than referencing or something
// - can't use std without tricks because of a lack of comptime in the
//   comparator signature
fn sorted_types(comptime n: usize, comptime items: [n]type) [n]type {
    comptime var result: [n]type = items;
    comptime var i = 1;
    inline while (i < items.len) : (i += 1) {
        comptime var j = i;
        inline while (j > 0 and comptime type_lt(result[j], result[j - 1])) : (j -= 1) {
            const z = result[j];
            result[j] = result[j - 1];
            result[j - 1] = z;
        }
    }
    return result;
}

test "type sort" {
    // no clue what the sort order actually is, so we'll just see what we get,
    // scramble the results, and see if we can get the same answer
    const A = opaque {};
    const AA = opaque {};
    const AB = opaque {};

    comptime var types: [3]type = .{ AA, AB, A };
    types = sorted_types(types.len, types);

    const a = types[0];
    const b = types[1];
    const c = types[2];

    types[0] = b;
    types[1] = c;
    types[2] = a;
    types = sorted_types(types.len, types);

    try std.testing.expectEqual(types[0], a);
    try std.testing.expectEqual(types[1], b);
    try std.testing.expectEqual(types[2], c);
}

pub inline fn Constraint(comptime wrapped: type, comptime types: anytype) type {
    comptime var idx: [types.len]type = undefined;
    for (idx[0..], types) |*x, T|
        x.* = T;
    return _Constraint(wrapped, sorted_types(types.len, idx));
}

pub inline fn constrain(comptime T: type, val: T, comptime constraints: anytype) Constraint(T, constraints) {
    const C = Constraint(T, constraints);
    return C{ .val = val };
}

inline fn _Constraint(comptime wrapped: type, comptime types: anytype) type {
    return struct {
        val: wrapped,

        pub inline fn as(self: @This(), comptime C: type) C {
            comptime if (!check(C.list())) {
                @compileError("Incompatible projection from " ++ @typeName(@This()) ++ " to " ++ @typeName(C));
            };
            return C{ .val = self.val };
        }

        pub inline fn restrict(self: @This(), comptime constraints: anytype) Constraint(wrapped, constraints) {
            const C = Constraint(wrapped, constraints);
            return self.as(C);
        }

        pub inline fn expand(self: @This(), comptime constraints: anytype) Constraint(wrapped, merge(types, constraints)) {
            const C = Constraint(wrapped, merge(types, constraints));
            return C{ .val = self.val };
        }

        pub inline fn extract(self: @This(), comptime constraints: anytype) wrapped {
            return self.restrict(constraints).val;
        }

        inline fn check(comptime constraints: anytype) bool {
            outer: for (constraints) |C| {
                for (types) |T| {
                    if (C == T) {
                        continue :outer;
                    }
                }
                return false;
            }
            return true;
        }

        inline fn list() @TypeOf(types) {
            return types;
        }
    };
}

inline fn Merge(comptime A: anytype, comptime B: anytype) type {
    comptime var i = A.len;
    outer: for (B) |b| {
        for (A) |a| {
            if (a == b) {
                continue :outer;
            }
        }
        i += 1;
    }
    return [i]type;
}

inline fn merge(comptime A: anytype, comptime B: anytype) Merge(A, B) {
    comptime var rtn: Merge(A, B) = undefined;
    for (A, 0..) |a, i|
        rtn[i] = a;
    comptime var j = A.len;
    outer: for (B) |b| {
        for (A) |a| {
            if (a == b) {
                continue :outer;
            }
        }
        rtn[j] = b;
        j += 1;
    }
    return rtn;
}

test "doesn't crash" {
    // This is a twidge hard to test because by design it causes compile
    // errors. The core compileError mechanism is simple and hard to
    // ignore though, so we'll assume it works, and this test just checks
    // that the public API does everything it should without crashing and
    // produces types which evaluate as equal to each other when appropriate.
    const NonEmpty = struct {};
    const AllPositive = struct {};
    const AllEven = struct {};

    var data = [_]u8{ 2, 4, 6 };
    var safe_data = constrain([]u8, data[0..], .{ NonEmpty, AllPositive });

    var safer_data = safe_data.expand(.{AllEven});
    var even_data = safer_data.restrict(.{AllEven});
    var even_val = even_data.extract(.{AllEven});

    try std.testing.expectEqual(
        Constraint([]u8, .{ NonEmpty, AllPositive, AllEven }),
        @TypeOf(safer_data),
    );

    try std.testing.expectEqual(
        Constraint([]u8, .{AllEven}),
        @TypeOf(even_data),
    );

    try std.testing.expectEqual(
        []u8,
        @TypeOf(even_val),
    );

    const also_even = safer_data.as(@TypeOf(even_data));
    try std.testing.expectEqual(
        @TypeOf(also_even),
        @TypeOf(even_data),
    );
}

test "canonicalization" {
    try std.testing.expectEqual(
        Constraint(void, .{ u8, u16 }),
        Constraint(void, .{ u16, u8 }),
    );

    try std.testing.expect(Constraint(void, .{ u8, u16 }) != Constraint(void, .{ u8, u24 }));
}
