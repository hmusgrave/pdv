# pdv

parse don't validate

## Purpose

The [Parse Don't Validate paper](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/) did the rounds again recently, and some insightful commenter asked what would happen if you had a combinatorial explosion of properties you would want to parse rather than validate. This has always been my problem with the idea, but with Zig I think you can make that explosion of types ergonomic, useful, and zero-cost. This library handles the details so you don't have to.

## Installation

Choose your favorite method for vendoring this code into your repository. I've been using [zigmod](https://github.com/nektro/zigmod) lately, and it's pretty painless. I also generally like [git-subrepo](https://github.com/ingydotnet/git-subrepo), copy-paste is always a winner, and whenever the official package manager is up we'll be there too.

Note: I wrote this targeting an 0.11-dev Zig compiler, and it seems Zigmod isn't compatible with those beta releases yet. The only breaking changes I think I'm using are the build syntax and new for loops, but installation might be hairy for the time being.

## Examples
```zig
const std = @import("std");
const pdv = @import("pdv");

const NonEmpty = struct {};
const AllPositive = struct {};

fn arr_min(comptime T: type, wrapped_data: pdv.Constraint([]T, .{NonEmpty})) T {
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

fn parse_contains_all_positives(comptime T: type, data: []T) ?pdv.Constraint([]T, .{NonEmpty, AllPositive}) {
    if (data.len == 0)
        return null;
    var non_empty_data = pdv.constrain([]T, data, .{NonEmpty});

    for (data) |x| {
        if (x <= 0)
	    return null;
    }
    var all_positives = non_empty_data.expand(.{AllPositive});
    
    // or return pdv.Constraint([]T, .{NonEmpty, AllPositive}){.val = data};
    return all_positives;
}

test "something" {
    const data = [_]u8{1, 2, 3};

    // real-world code might need to handle errors, but our example by construction
    // is non-empty and all-positive
    const parsed_data = parse_contains_all_positives(u8, data[0..]) orelse unreachable;

    // it's easy to type-erase the fact that the entries are positive to satisfy
    // the non-emptiness our `arr_min` function requires
    //
    // alternatively, arr_min(parsed_data.as(pdv.Constraint([]u8, .{NonEmpty})))
    const min = arr_min(parsed_data.restrict(.{NonEmpty}));

    // sanity-check that we did something
    try std.testing.expectEqual(min, 1);
}
```

## Status
Work has me pretty busy lately, so I might have a few weeks lead time on any responses. Also note that we don't do anything special with respect to canonicalization, so the following will fail to type-check because the orders don't match:

```zig
fn foo(_: pdv.Constraint(u8, .{Positive, Even})) void {}

test "foo" {
    const x: u8 = 4;

    // Note that `Positive` and `Even` have swapped positions with respect
    // to their order in the type signature of `foo`
    const pos_even_x = pdv.constrain(u8, x, .{Even, Positive});

    foo(pos_even_x);  // compile error
    foo(pos_even_x.restrict(.{Positive, Even}));  // succeeds because we match the order in `foo`
}
```
