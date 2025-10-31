# Yes - Stand for nothing I just tought it was funny

```
zig fetch --save git+https://github.com/HaraldWik/yes
```

**build.zig**
```
const yes = b.dependency("yes", .{ .target = target, .optimize = optimize }).module("yes");
```

**main.zig**
```
const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    // next returns null on exit
    while (window.next()) |event| {
        _ = event;
    } else std.debug.print("Exit!\n", .{});
}

```

Windows,
Linux, Unix - X11 

Thanks to 
Leandros for the windows headers! [here](https://github.com/Leandros/WindowsHModular/)