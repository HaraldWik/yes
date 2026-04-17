# Yes - Yet Another Event System
Originally did not stand for anything.

## Installation

```
zig fetch --save git+https://github.com/HaraldWik/yes
```

**build.zig**
```zig
const yes = b.dependency("yes", .{ 
    .target = target,
    .optimize = optimize
    // Recommend xcb unless you want OpenGL in which case you will have to use xlib.
    // The xpz platform is very early stage and not at all recommended, it does not support OpenGL or Vulkan
    // .x_backend = <none, xcb, xlib, xpz>
    // .wayland_backend = <none, libwayland>
}).module("yes");
```

## Examples

```zig
const std = @import("std");
const yes = @import("yes");

// example args "zig build run -- --xdg=wayland"
// example args "zig build run -- --xdg=x11"
// if none are selected it will detect it in yes.Platform.unix.SessionType

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Use he cross platform platform, which will do all the work behind the scenes
    // i.e detect if its Wayland or X, automaticaly pick which platform depending on Os tag and Abi
    var cross_platform: yes.Platform.Cross = try .init(gpa, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window: yes.Platform.Cross.Window = .empty(platform);
    const window = cross_window.interface(platform);
    try window.open(platform, .{
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window.close(platform);

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("{any}", .{event}),
        };
    }
}
```



NOTE: Does not show anything on wayland, because wayland does not render empty windows.

[Example here](https://github.com/HaraldWik/yes/blob/master/examples/simple/src/main.zig)

[Wayland example here](https://github.com/HaraldWik/yes/blob/master/examples/framebuffer_simple/src/main.zig) (framebuffer)

## Interfaces

Yes is built around the idea that everything is an interface. The window itself is an intrusive interface, meaning platform backends implement and extend it directly rather than being wrapped behind a rigid abstraction.

This design makes it possible to implement custom platforms tailored to your needs—whether for experimentation, minimal setups, or supporting unusual environments.

As an example, there is a [GLFW](https://www.glfw.org/) backend. 
It implements only a small subset of functionality and mainly serves as a demonstration of how a platform backend can be integrated into Yes.

## Features 

✅ fully supported
⚠️ partially supported
❌ not supported

| Window Property Setting              |Windows |Wayland | XCB  | Xlib | XPZ  |Cocoa (Mac) |
|--------------------------------------|:------:|:------:|:----:|:----:|:----:|:----------:|
| Title                                |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Size                                 |   ✅   |   ❌   |  ✅  |  ✅  |  ❌  |     ❌     |
| Position                             |   ✅   |   ❌   |  ✅  |  ✅  |  ❌  |     ❌     |
| Resize Policy (max, min, resizable)  |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Fullscreen                           |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Maximize                             |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Minimize                             |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Focus                                |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Always On Top                        |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Float                                |   ❌   |   ⚠️   |  ❌  |  ✅  |  ❌  |     ❌     |
| Decorate                             |   ❌   |   ⚠️   |  ✅  |  ✅  |  ❌  |     ❌     |
| Cursor (arrow, text, hand, etc.)     |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |

| Window Events                        |Windows |Wayland | XCB  | Xlib | XPZ  |Cocoa (Mac) |
|--------------------------------------|:------:|:------:|:----:|:----:|:----:|:----------:|
| Close                                |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Resize                               |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Move                                 |   ✅   |   ❌   |  ✅  |  ✅  |  ✅  |     ❌     |
| Focus                                |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Key                                  |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Mouse Motion                         |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Mouse Scroll                         |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Mouse Button                         |   ✅   |   ✅   |  ✅  |  ✅  |  ✅  |     ❌     |
| Touch Down                           |   ✅   |   ✅   |  ❌  |  ✅  |  ❌  |     ❌     |
| Touch Up                             |   ✅   |   ✅   |  ❌  |  ✅  |  ❌  |     ❌     |
| Touch Motion                         |   ✅   |   ✅   |  ❌  |  ✅  |  ❌  |     ❌     |

| Window Surface Types                 |Windows |Wayland | XCB  | Xlib | XPZ  |Cocoa (Mac) |
|--------------------------------------|:------:|:------:|:----:|:----:|:----:|:----------:|
| Framebuffer                          |   ❌   |   ✅   |  ❌  |  ❌  |  ❌  |     ❌     |
| OpenGL                               |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Vulkan                               |   ✅   |   ✅   |  ✅  |  ✅  |  ❌  |     ❌     |
| Direct3D                             |   ⚠️   |   ❌   |  ❌  |  ❌  |  ❌  |     ❌     |
| Metal                                |   ❌   |   ❌   |  ❌  |  ❌  |  ❌  |     ❌     |

## Plans

The goal is to continue improving the library by adding support for more features and platforms like android, ios.

macOS support may be added in the future, although I currently do not have access to a Mac for testing, huge thanks to anyone who is willing to help with this.

A major focus in the near future will be implementing clipboard support and file drag-and-drop, as well as extending framebuffer rendering to more platforms.

*If you have a feature request or encounter any issues, feel free to open an issue. I’ll try to address it as soon as possible. You can also reach on the [zig discord](https://discord.com/channels/605571803288698900/1478476506274464000)* 
