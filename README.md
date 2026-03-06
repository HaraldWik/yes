# Yes - Stand for nothing I just tought it was funny

```
zig fetch --save git+https://github.com/HaraldWik/yes
```

**build.zig**
```
const yes = b.dependency("yes", .{ .target = target, .optimize = optimize }).module("yes");
```

[Example here](https://github.com/HaraldWik/yes/blob/version2/examples/v2/src/main.zig)

## Pre supported platforms include
Windows
Xorg
Wayland

### You can add more platforms since its all interfaced