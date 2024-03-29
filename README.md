# pdv

parse don't validate

## Purpose

The [Parse Don't Validate paper](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) did the rounds again recently, and some insightful commenter asked what would happen if you had a combinatorial explosion of properties you would want to parse rather than validate. This has always been my problem with the idea, but with Zig I think you can make that explosion of types ergonomic, useful, and zero-cost. This library handles the details so you don't have to.

## Installation

Zig has a package manager!!! Do something like the following.

```zig
// build.zig.zon
.{
    .name = "foo",
    .version = "0.0.0",

    .dependencies = .{
        .pdv = .{
	    .url = "https://github.com/hmusgrave/pdv/archive/refs/tags/1.0.tar.gz",
	    .hash = "1220910f59739daa29dccc0d01743b4930dab6ba4e47ae1ffd4872076cecc8581c82",
        },
    },
}
```

```zig
// build.zig
const pdv_pkg = b.dependency("pdv", .{
    .target = target,
    .optimize = optimize,
});
const pdv_mod = pdv_pkg.module("pdv");
exe.addModule("pdv", pdv_mod);
unit_tests.addModule("pdv", pdv_mod);
```

## Examples
```zig
const std = @import("std");
const pdv = @import("pdv");

const NonEmpty = struct {};
const AllPositive = struct {};

fn arr_min(comptime T: type, wrapped_data: pdv.Constraint([]const T, .{NonEmpty})) T {
    // unwrap the data, and optionally check any constraints you would
    // like to ensure it satisfies
    const data = wrapped_data.extract(.{NonEmpty});

    // the type system already guaranteed the data is non-empty, so we
    // can blindly extract the first element without fear of panics or
    // errors
    var min = data[0];
    for (data[1..]) |x|
        min = @min(min, x);

    // note that there isn't a default argument or an optional/error return
    // type since the fact that the input is nonempty means we can guarantee
    // a valid return value exists
    return min;
}

fn parse_contains_all_positives(comptime T: type, data: []const T) ?pdv.Constraint([]const T, .{ NonEmpty, AllPositive }) {
    if (data.len == 0)
        return null;
    var non_empty_data = pdv.constrain([]const T, data, .{NonEmpty});

    for (data) |x| {
        if (x <= 0)
            return null;
    }
    var all_positives = non_empty_data.expand(.{AllPositive});

    // or return pdv.Constraint([]const T, .{NonEmpty, AllPositive}){.val = data};
    return all_positives;
}

test "something" {
    const data = [_]u8{ 1, 2, 3 };

    // real-world code might need to handle errors, but our example by construction
    // is non-empty and all-positive
    const parsed_data = parse_contains_all_positives(u8, data[0..]) orelse unreachable;

    // it's easy to type-erase the fact that the entries are positive to satisfy
    // the non-emptiness our `arr_min` function requires
    //
    // alternatively, arr_min(u8, parsed_data.as(pdv.Constraint([]const u8, .{NonEmpty})))
    const min = arr_min(u8, parsed_data.restrict(.{NonEmpty}));

    // sanity-check that we did something
    try std.testing.expectEqual(min, 1);
}
```

## Status
Updated for `zig-0.12.0-dev.86+197d9a9eb`.
