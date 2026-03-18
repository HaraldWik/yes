const std = @import("std");
const win32 = @import("win32").everything;
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

allocator: std.mem.Allocator,
instance: std.os.windows.HINSTANCE,
wglSwapIntervalEXT: ?*const fn (i32) callconv(.winapi) win32.BOOL = null,

pub const Window = struct {
    interface: Platform.Window = .{},
    class: win32.WNDCLASSEXW = undefined,
    hwnd: std.os.windows.HWND = undefined,
    surface: Surface = .empty,

    previous_style: i32 = 0,
    previous_placement: win32.WINDOWPLACEMENT = std.mem.zeroInit(win32.WINDOWPLACEMENT, .{ .length = @sizeOf(win32.WINDOWPLACEMENT) }),
    size_data: SizeData = undefined,

    pub const Surface = union(enum) {
        empty: void,
        opengl: OpenGL,

        pub const OpenGL = struct {
            device_context: std.os.windows.HDC = undefined,
            render_context: std.os.windows.HGLRC = undefined,
        };
    };

    pub const SizeData = struct {
        size: Platform.Window.Size,
        resize_policy: Platform.Window.ResizePolicy,
    };
};

/// Alternativly you can use winMain to get the HINSTANCE
pub fn get(allocator: std.mem.Allocator) !@This() {
    const instance: std.os.windows.HINSTANCE = @ptrCast(win32.GetModuleHandleW(null) orelse return error.GetInstanceHandle);
    return .{ .allocator = allocator, .instance = instance };
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = openglGetProcAddress,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.size_data = .{
        .size = options.size,
        .resize_policy = options.resize_policy,
    };

    window.class = std.mem.zeroInit(win32.WNDCLASSEXW, .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .lpszClassName = win32.L("WindowClass"),
        .lpfnWndProc = wndProc,
        .hInstance = self.instance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .style = win32.WNDCLASS_STYLES{
            .OWNDC = if (window.surface == .opengl) 1 else 0,
        },
    });
    if (!win32.SUCCEEDED(win32.RegisterClassExW(@ptrCast(&window.class)))) return error.RegisterClass;
    const title = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, options.title);

    window.hwnd = @ptrCast(win32.CreateWindowExW(
        .{ .TRANSPARENT = 1 },
        window.class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        if (options.position) |position| position.x else win32.CW_USEDEFAULT,
        if (options.position) |position| position.y else win32.CW_USEDEFAULT,
        @intCast(options.size.width),
        @intCast(options.size.height),
        null,
        null,
        self.instance,
        null,
    ) orelse return reportErr(error.CreateWindowFailed));

    self.allocator.free(title);

    switch (options.surface_type) {
        .empty => {},
        .software => {},
        .opengl => |version| {
            const dc: win32.HDC = win32.GetDC(@ptrCast(window.hwnd)) orelse return error.GetDeviceContext;

            const desired_pixel_format: *const win32.PIXELFORMATDESCRIPTOR = &std.mem.zeroInit(win32.PIXELFORMATDESCRIPTOR, .{
                .nSize = @sizeOf(win32.PIXELFORMATDESCRIPTOR),
                .nVersion = 1,
                .dwFlags = .{
                    .DRAW_TO_WINDOW = 1,
                    .SUPPORT_OPENGL = 1,
                    .DOUBLEBUFFER = 1,
                },
                .iPixelType = win32.PFD_TYPE_RGBA,
                .cColorBits = 32,
                .cDepthBits = 24,
                .cStencilBits = 8,
                .cAlphaBits = 8,
                .iLayerType = win32.PFD_MAIN_PLANE,
            });

            const suggested_pixel_format_index: i32 = win32.ChoosePixelFormat(dc, desired_pixel_format);
            var suggested_pixel_format: win32.PIXELFORMATDESCRIPTOR = undefined;

            const DescribePixelFormat = @extern(*const fn (hdc: ?win32.HDC, iPixelFormat: i32, nBytes: u32, ppfd: ?*win32.PIXELFORMATDESCRIPTOR) callconv(.winapi) i32, .{ .name = "DescribePixelFormat", .library_name = "gdi32" });

            if (!win32.SUCCEEDED(DescribePixelFormat(dc, suggested_pixel_format_index, @sizeOf(win32.PIXELFORMATDESCRIPTOR), &suggested_pixel_format))) return error.DescribePixelFormat;
            if (!win32.SUCCEEDED(win32.SetPixelFormat(dc, suggested_pixel_format_index, desired_pixel_format))) return error.SetPixelFormat;

            var rc: win32.HGLRC = win32.wglCreateContext(dc) orelse return error.WglCreateContext;
            if (!win32.SUCCEEDED(win32.wglMakeCurrent(dc, rc))) return error.WglMakeCurrent;

            const getExtensionsStringARB: *const fn (win32.HDC) callconv(.winapi) ?[*:0]const u8 = @ptrCast(win32.wglGetProcAddress("wglGetExtensionsStringARB") orelse return error.WglGetProcAddress);

            var createContextAttribsARB: ?*const fn (win32.HDC, ?win32.HGLRC, [*:0]const i32) callconv(.winapi) ?win32.HGLRC = null;

            if (getExtensionsStringARB(dc)) |extensions| {
                var it = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (it.next()) |name| {
                    if (std.mem.eql(u8, name, "WGL_EXT_swap_control"))
                        self.wglSwapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT") orelse return error.WglSwapIntervalEXT);
                    // if (std.mem.eql(u8, name, "WGL_ARB_pixel_format"))
                    // wgl.choosePixelFormatARB = @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB") orelse return error.WglChoosePixelFormatARB);
                    if (std.mem.eql(u8, name, "WGL_ARB_create_context_profile"))
                        createContextAttribsARB = @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB") orelse return error.WglCreateContextAttribsARB);
                }
            }

            const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
            const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
            const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
            const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;

            const attributes: [:0]const i32 = &.{
                WGL_CONTEXT_MAJOR_VERSION_ARB, @intCast(version.major),
                WGL_CONTEXT_MINOR_VERSION_ARB, @intCast(version.minor),
                WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            };

            if (createContextAttribsARB) |createContextAttribs| {
                _ = win32.wglDeleteContext(rc);
                rc = createContextAttribs(dc, null, attributes) orelse return error.CreateModernOpenGL;
                _ = win32.wglMakeCurrent(dc, rc);
            }

            window.surface = .{ .opengl = .{ .device_context = @ptrCast(dc), .render_context = @ptrCast(rc) } };
        },
        .vulkan => {},
        .direct3d => {},
    }

    _ = win32.ShowWindow(@ptrCast(window.hwnd), .{ .SHOWNORMAL = 1 });
    if (!win32.SUCCEEDED(win32.UpdateWindow(@ptrCast(window.hwnd)))) return error.UpdateWindow;

    try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });
}
fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.surface == .opengl) {
        _ = win32.wglDeleteContext(@ptrCast(window.surface.opengl.render_context));
        _ = win32.ReleaseDC(@ptrCast(window.hwnd), @ptrCast(window.surface.opengl.device_context));
    }

    _ = win32.DestroyWindow(@ptrCast(window.hwnd));
    _ = win32.UnregisterClassW(window.class.lpszClassName, @ptrCast(self.instance));
}
fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;

    var msg: win32.MSG = undefined;
    if (win32.PeekMessageW(&msg, @ptrCast(window.hwnd), 0, 0, .{ .REMOVE = 1 }) == 0) return null;
    _ = win32.TranslateMessage(&msg);
    _ = win32.DispatchMessageW(&msg);

    return switch (msg.message) {
        win32.WM_USER + win32.WM_GETMINMAXINFO => {
            var mmi: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @intCast(msg.lParam)));

            const max_size: ?Platform.Window.Size, const min_size: ?Platform.Window.Size = switch (window.size_data.resize_policy) {
                .resizable => |resizable| if (resizable) return null else .{ window.interface.size, window.interface.size },
                .specified => |specified| .{ specified.max_size, specified.min_size },
            };

            if (max_size) |size| {
                mmi.ptMaxTrackSize.x = @intCast(size.width); // maximum width
                mmi.ptMaxTrackSize.y = @intCast(size.height); // maximum height
            }
            if (min_size) |size| {
                mmi.ptMinTrackSize.x = @intCast(size.width); // minimum width
                mmi.ptMinTrackSize.y = @intCast(size.height); // minimum height
            }

            _ = win32.DefWindowProcW(@ptrCast(window.hwnd), win32.WM_GETMINMAXINFO, msg.wParam, msg.lParam);

            return null;
        },
        win32.WM_DESTROY => .close,
        win32.WM_SYSCOMMAND => switch (msg.wParam) {
            win32.SC_CLOSE => .close,
            else => {
                std.log.warn("unknown WM_SYSCOMMAND: {d}", .{msg.wParam});
                return null;
            },
        },
        win32.WM_USER + win32.WM_SETFOCUS => .{ .focus = .focused },
        win32.WM_USER + win32.WM_KILLFOCUS => .{ .focus = .unfocused },
        win32.WM_USER + win32.WM_SIZE => .{ .resize = .{
            .width = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam))))),
            .height = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam >> 16))))),
        } },
        win32.WM_USER + win32.WM_MOVE => .{ .move = .{
            .x = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam) orelse return null))),
            .y = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam >> 16) orelse return null))),
        } },
        win32.WM_WINDOWPOSCHANGED => {
            std.debug.panic("WM_WINDOWPOSCHANGED", .{});
            return null;
        },
        // Mouse
        win32.WM_MOUSEMOVE => .{ .mouse_motion = .{
            .x = @floatFromInt(@as(u16, @truncate(@as(usize, @intCast(msg.lParam))))),
            .y = @floatFromInt(@as(u16, @truncate(@as(usize, @intCast(msg.lParam >> 16))))),
        } },
        win32.WM_MOUSEWHEEL, win32.WM_MOUSEHWHEEL => {
            const delta: isize = @intCast((msg.wParam >> 16) & 0xFFFF);
            var lines: isize = @intCast(@divTrunc(delta, @as(isize, @intCast(win32.WHEEL_DELTA)))); // lines > 0 -> scroll right, lines < 0 -> left
            if (lines == 545) lines = -1;
            return .{
                .mouse_scroll = switch (msg.message) {
                    win32.WM_MOUSEWHEEL => .{ .horizontal = @floatFromInt(lines) },
                    win32.WM_MOUSEHWHEEL => .{ .vertical = @floatFromInt(lines) },
                    else => unreachable,
                },
            };
        },
        win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => |button| .{
            .mouse_button = .{
                .state = switch (msg.message) {
                    win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN => .pressed,
                    win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => .released,
                    else => unreachable,
                },
                .button = Platform.Window.Event.MouseButton.Button.fromWin32(button, msg.wParam) orelse return null,
            },
        },

        // Key
        win32.WM_KEYDOWN, win32.WM_KEYUP => {
            const sym = Platform.Window.Event.Key.Sym.fromWin32(std.enums.fromInt(win32.VIRTUAL_KEY, msg.wParam).?, msg.lParam) orelse return null;
            // switch (msg.message) {
            //     win32.WM_KEYDOWN => {
            //         if (keyboard.keys[@intFromEnum(sym)] == .pressed) return null;
            //         keyboard.keys[@intFromEnum(sym)] = .pressed;
            //     },
            //     win32.WM_KEYUP => keyboard.keys[@intFromEnum(sym)] = .released,
            //     else => unreachable,
            // }
            return .{ .key = .{
                .state = switch (msg.message) {
                    win32.WM_KEYDOWN => .pressed,
                    win32.WM_KEYUP => .released,
                    else => unreachable,
                },
                .code = @intCast((msg.lParam >> @intCast(16)) & 0xFF),
                .sym = sym,
            } };
        },
        else => null,
    };
}
fn windowSetProperty(context: *anyopaque, platform_window: *Platform.Window, property: Platform.Window.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            const title_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, title);
            defer self.allocator.free(title_utf16);
            _ = win32.SetWindowTextW(@ptrCast(window.hwnd), @ptrCast(title_utf16));
        },
        .size => |size| _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, 0, 0, @intCast(size.width), @intCast(size.height), .{ .NOZORDER = 1, .NOMOVE = 1 }),
        .position => |position| _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, position.x, position.y, 0, 0, .{ .NOZORDER = 1, .NOSIZE = 1 }),
        .resize_policy => |resize_policy| window.size_data.resize_policy = resize_policy,
        .fullscreen => |fullscreen| if (fullscreen) {
            _ = win32.GetWindowPlacement(@ptrCast(window.hwnd), &window.previous_placement);

            const style = win32.GetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE);
            window.previous_style = style;
            const new_style = (style & ~@as(i32, @bitCast(win32.WS_OVERLAPPEDWINDOW))) | @as(i32, @bitCast(win32.WS_POPUP));

            _ = win32.SetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE, new_style);

            const monitor = win32.MonitorFromWindow(@ptrCast(window.hwnd), win32.MONITOR_DEFAULTTOPRIMARY);
            var mi: win32.MONITORINFO = std.mem.zeroInit(win32.MONITORINFO, .{
                .cbSize = @sizeOf(win32.MONITORINFO),
            });
            _ = win32.GetMonitorInfoW(monitor, &mi);

            _ = win32.SetWindowPos(
                @ptrCast(window.hwnd),
                null,
                mi.rcMonitor.left,
                mi.rcMonitor.top,
                mi.rcMonitor.right - mi.rcMonitor.left,
                mi.rcMonitor.bottom - mi.rcMonitor.top,
                .{ .DRAWFRAME = 1, .NOOWNERZORDER = 1 },
            );
        } else { // unfullscreen
            _ = win32.SetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE, window.previous_style);
            _ = win32.SetWindowPlacement(@ptrCast(window.hwnd), &window.previous_placement);
            _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, 0, 0, 0, 0, .{ .DRAWFRAME = 1, .NOMOVE = 1, .NOSIZE = 1, .NOZORDER = 1, .NOOWNERZORDER = 1 });
        },
        .maximized => |maximized| _ = win32.ShowWindow(@ptrCast(window.hwnd), if (maximized) win32.SW_MAXIMIZE else win32.SW_RESTORE),
        .minimized => |minimized| _ = win32.ShowWindow(@ptrCast(window.hwnd), if (minimized) win32.SW_MINIMIZE else win32.SW_RESTORE),
        .always_on_top => |always_on_top| _ = win32.SetWindowPos(@ptrCast(window.hwnd), if (always_on_top) win32.HWND_TOPMOST else win32.HWND_NOTOPMOST, 0, 0, 0, 0, .{ .NOMOVE = 1, .NOSIZE = 1 }),
        .floating => {},
        .decorated => |decorated| {
            var style: i32 = @bitCast(win32.GetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE));
            const WS_CAPTION: i32 = 0x00C00000;
            const WS_THICKFRAME: i32 = 0x00040000;

            if (decorated)
                style |= (WS_CAPTION | WS_THICKFRAME)
            else
                style &= ~(WS_CAPTION | WS_THICKFRAME);

            _ = win32.SetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE, @bitCast(style));
            _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, 0, 0, 0, 0, .{ .NOMOVE = 1, .NOSIZE = 1, .NOZORDER = 1, .DRAWFRAME = 1 });
        },
        .focus => {}, // TODO: add focus request
    }
}
fn windowFramebuffer(context: *anyopaque, platform_window: *Platform.Window) anyerror!Platform.Window.Framebuffer {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;

    std.log.info("no software rendering is currently not supported", .{});

    return undefined;
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    const gl = window.surface.opengl;
    if (!win32.SUCCEEDED(win32.wglMakeCurrent(@ptrCast(gl.device_context), @ptrCast(gl.render_context)))) return reportErr(error.WglMakeCurrent);
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    const gl = window.surface.opengl;
    if (!win32.SUCCEEDED(win32.SwapBuffers(@ptrCast(gl.device_context)))) return reportErr(error.WglSwapBuffers);
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *Platform.Window, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    std.debug.assert(window.surface == .opengl);
    std.debug.assert(self.wglSwapIntervalEXT != null);

    if (!win32.SUCCEEDED(self.wglSwapIntervalEXT.?(interval))) return reportErr(error.WglMakeCurrent);
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *Platform.Window, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const vkCreateWin32SurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateWin32SurfaceKHR") orelse return error.LoadVkCreateWin32SurfaceKHR);

    const create_info: vulkan.Surface.CreateInfo = .{
        .hinstance = self.instance,
        .hwnd = window.hwnd,
    };

    var surface: ?*vulkan.Surface = null;
    if (vkCreateWin32SurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateWin32SurfaceKHR;
    return surface orelse error.InvalidSurface;
}

fn openglGetProcAddress(procname: [*:0]const u8) callconv(opengl.APIENTRY) ?opengl.Proc {
    if (opengl.wglGetProcAddress(procname)) |proc| return @ptrCast(proc);
    const gl = win32.LoadLibraryA("opengl32.dll") orelse return null;
    if (win32.GetProcAddress(gl, procname)) |proc| return @ptrCast(proc);
    return null;
}

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    return switch (msg) {
        win32.WM_GETMINMAXINFO, win32.WM_SIZE, win32.WM_MOVE, win32.WM_SETFOCUS, win32.WM_KILLFOCUS => |wm| {
            if (!win32.SUCCEEDED(win32.PostMessageW(hwnd, win32.WM_USER + wm, wParam, lParam))) reportErr(error.PostMessage) catch {};
            return 0;
        },
        else => win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    };
}

pub fn reportErr(err: anyerror) anyerror {
    @branchHint(.unlikely);

    const code = win32.GetLastError();

    var text_buffer: [512:0]u16 = undefined;
    const text_len = win32.FormatMessageW(
        .{ .FROM_SYSTEM = 1, .IGNORE_INSERTS = 1 },
        null,
        @intFromEnum(code),
        0,
        @ptrCast(&text_buffer),
        text_buffer.len,
        null,
    );
    const error_name = @errorName(err);
    var title_buffer: [256]u16 = undefined;
    const title = title_buffer[0..(try std.unicode.utf8ToUtf16Le(&title_buffer, error_name[0 .. error_name.len + 1]))];

    _ = win32.MessageBoxW(
        null,
        @ptrCast(text_buffer[0..text_len]),
        @ptrCast(title),
        .{ .ICONHAND = 1 },
    );

    return err;
}

pub fn checkError() !void {
    @branchHint(.unlikely);
    const scope = std.log.scoped(.win32);
    const err = std.os.windows.GetLastError();
    if (err == .SUCCESS) return;

    scope.err("{s}", .{@tagName(err)});
    return error.Win32;
}
