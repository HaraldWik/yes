const Win32 = @This();

const std = @import("std");
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Desktop = @import("../Desktop.zig");
const DesktopWindow = @import("../Window.zig");
const win32 = @import("win32").everything;

// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

gpa: std.mem.Allocator,
hinstance: std.os.windows.HINSTANCE,
wglSwapIntervalEXT: ?*const fn (i32) callconv(.winapi) win32.BOOL = null,
cursors: struct {
    arrow: ?std.os.windows.HCURSOR = null,
    text: ?std.os.windows.HCURSOR = null,
    hand: ?std.os.windows.HCURSOR = null,
    grab: ?std.os.windows.HCURSOR = null,
    crosshair: ?std.os.windows.HCURSOR = null,
    wait: ?std.os.windows.HCURSOR = null,
    resize_ns: ?std.os.windows.HCURSOR = null,
    resize_ew: ?std.os.windows.HCURSOR = null,
    resize_nesw: ?std.os.windows.HCURSOR = null,
    resize_nwse: ?std.os.windows.HCURSOR = null,
    forbidden: ?std.os.windows.HCURSOR = null,
    move: ?std.os.windows.HCURSOR = null,
    grabbing: ?std.os.windows.HCURSOR = null,
} = .{},

pub const Window = struct {
    interface: DesktopWindow = .{},
    class: win32.WNDCLASSEXW = undefined,
    hwnd: std.os.windows.HWND = undefined,
    surface: Surface = .empty,

    previous_style: i32 = 0,
    previous_placement: win32.WINDOWPLACEMENT = std.mem.zeroInit(win32.WINDOWPLACEMENT, .{ .length = @sizeOf(win32.WINDOWPLACEMENT) }),
    size_data: SizeData = undefined,

    cursor: std.os.windows.HCURSOR = undefined,

    pub const Surface = union(enum) {
        empty: void,
        opengl: OpenGL,

        pub const OpenGL = struct {
            device_context: std.os.windows.HDC = undefined,
            render_context: std.os.windows.HGLRC = undefined,
        };
    };

    pub const SizeData = struct {
        size: DesktopWindow.Size,
        resize_policy: DesktopWindow.ResizePolicy,
    };
};

/// Alternativly you can use winMain to get the HINSTANCE
pub fn init(gpa: std.mem.Allocator) !Win32 {
    const instance: std.os.windows.HINSTANCE = @ptrCast(win32.GetModuleHandleW(null) orelse return error.GetInstanceHandle);
    return .{
        .gpa = gpa,
        .hinstance = instance,
    };
}

pub fn deinit(self: Win32) void {
    inline for (std.meta.fields(self.cursors)) |field| {
        if (@field(self.cursors, field)) |cursor| win32.DestroyCursor(cursor);
    }
}

pub fn platform(self: *Win32) Desktop {
    return .{
        .userdata = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowFramebufferPresent = Desktop.noWindowFramebufferPresent,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = openglGetProcAddress,
        },
    };
}

fn windowOpen(userdata: ?*anyopaque, desktop_window: *DesktopWindow, options: DesktopWindow.OpenOptions) anyerror!void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    window.size_data = .{
        .size = options.size,
        .resize_policy = options.resize_policy,
    };

    window.class = std.mem.zeroInit(win32.WNDCLASSEXW, .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .lpszClassName = win32.L("WindowClass"),
        .lpfnWndProc = wndProc,
        .hInstance = self.hinstance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .style = win32.WNDCLASS_STYLES{
            .OWNDC = if (window.surface == .opengl) 1 else 0,
        },
    });
    if (!win32.SUCCEEDED(win32.RegisterClassExW(@ptrCast(&window.class)))) return error.RegisterClass;
    const title = try std.unicode.utf8ToUtf16LeAllocZ(self.gpa, options.title);

    window.hwnd = @ptrCast(win32.CreateWindowExW(
        .{ .TRANSPARENT = 1 },
        window.class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        if (options.position) |position| position.x else @max(0, @divTrunc(win32.GetSystemMetrics(.CXSCREEN) - @as(i32, @intCast(options.size.width)), 2)),
        if (options.position) |position| position.y else @max(0, @divTrunc(win32.GetSystemMetrics(.CYSCREEN) - @as(i32, @intCast(options.size.height)), 2)),
        @intCast(options.size.width),
        @intCast(options.size.height),
        null,
        null,
        self.hinstance,
        null,
    ) orelse return reportErr(error.CreateWindowFailed));

    self.gpa.free(title);

    var device = win32.RAWINPUTDEVICE{
        .usUsagePage = 0x01,
        .usUsage = 0x02,
        .dwFlags = .{},
        .hwndTarget = @ptrCast(window.hwnd),
    };

    _ = win32.RegisterRawInputDevices(@ptrCast(&device), 1, @sizeOf(win32.RAWINPUTDEVICE));

    switch (options.surface_type) {
        .empty => {},
        .framebuffer => {},
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
    _ = win32.RegisterTouchWindow(@ptrCast(window.hwnd), .FINETOUCH);

    try windowSetProperty(userdata, desktop_window, .{ .decorated = options.decorated });
}
fn windowClose(userdata: ?*anyopaque, desktop_window: *DesktopWindow) void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    if (window.surface == .opengl) {
        _ = win32.wglDeleteContext(@ptrCast(window.surface.opengl.render_context));
        _ = win32.ReleaseDC(@ptrCast(window.hwnd), @ptrCast(window.surface.opengl.device_context));
    }

    _ = win32.DestroyWindow(@ptrCast(window.hwnd));
    _ = win32.UnregisterClassW(window.class.lpszClassName, @ptrCast(self.hinstance));
}
fn windowPoll(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!?DesktopWindow.Event {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;

    var event: ?DesktopWindow.Event = null;

    while (event == null) {
        var msg: win32.MSG = undefined;
        if (win32.PeekMessageW(&msg, @ptrCast(window.hwnd), 0, 0, .{ .REMOVE = 1 }) == 0) return null;
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);

        switch (msg.message) {
            win32.WM_USER + win32.WM_GETMINMAXINFO => {
                var mmi: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @intCast(msg.lParam)));

                const max_size: ?DesktopWindow.Size, const min_size: ?DesktopWindow.Size = switch (window.size_data.resize_policy) {
                    .resizable => |resizable| if (resizable) continue else .{ window.interface.size, window.interface.size },
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
            },
            win32.WM_USER + win32.WM_CLOSE => event = .close,
            win32.WM_USER + win32.WM_SETFOCUS => {
                try windowSetProperty(userdata, desktop_window, .{ .cursor_mode = window.interface.cursor_mode });
                event = .{ .focus = true };
            },
            win32.WM_USER + win32.WM_KILLFOCUS => event = .{ .focus = false },
            win32.WM_USER + win32.WM_SIZE => event = .{ .resize = .{
                .width = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam))))),
                .height = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam >> 16))))),
            } },
            win32.WM_USER + win32.WM_MOVE => event = .{ .move = .{
                .x = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam) orelse continue))),
                .y = @intCast(@as(u16, @truncate(std.math.cast(u32, msg.lParam >> 16) orelse continue))),
            } },
            win32.WM_WINDOWPOSCHANGED => {
                std.debug.panic("WM_WINDOWPOSCHANGED", .{});
            },
            // Mouse
            win32.WM_MOUSEMOVE => event = .{ .mouse_motion = .{
                .x = @floatFromInt(@as(u16, @truncate(@as(usize, @intCast(msg.lParam))))),
                .y = @floatFromInt(@as(u16, @truncate(@as(usize, @intCast(msg.lParam >> 16))))),
            } },
            win32.WM_MOUSEWHEEL, win32.WM_MOUSEHWHEEL => {
                const delta: isize = @as(i16, @bitCast(@as(u16, @truncate(msg.wParam >> 16)))); // signed high word: up/right > 0, down/left < 0
                const lines: isize = @divTrunc(delta, @as(isize, @intCast(win32.WHEEL_DELTA)));
                event = .{
                    .mouse_scroll = switch (msg.message) {
                        win32.WM_MOUSEWHEEL => .{ .vertical = @floatFromInt(lines) },
                        win32.WM_MOUSEHWHEEL => .{ .horizontal = @floatFromInt(lines) },
                        else => unreachable,
                    },
                };
            },
            win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => |button| event = .{
                .mouse_button = .{
                    .state = switch (msg.message) {
                        win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN => .pressed,
                        win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => .released,
                        else => unreachable,
                    },
                    .button = DesktopWindow.Event.MouseButton.Button.fromWin32(button, msg.wParam) orelse continue,
                },
            },
            win32.WM_INPUT => {
                if (window.interface.cursor_mode != .captured and
                    window.interface.cursor_mode != .locked)
                    continue;

                var size: u32 = 0;

                // Get required buffer size
                _ = win32.GetRawInputData(
                    @ptrFromInt(@as(usize, @bitCast(msg.lParam))),
                    win32.RID_INPUT,
                    null,
                    &size,
                    @sizeOf(win32.RAWINPUTHEADER),
                );

                var buffer: [1024]u8 align(@alignOf(win32.RAWINPUT)) = undefined;

                const result = win32.GetRawInputData(
                    @ptrFromInt(@as(usize, @bitCast(msg.lParam))),
                    win32.RID_INPUT,
                    &buffer,
                    &size,
                    @sizeOf(win32.RAWINPUTHEADER),
                );

                if (result == -1) continue;

                const raw: *win32.RAWINPUT = @ptrCast(&buffer);

                if (raw.header.dwType != @as(u32, @intFromEnum(win32.RIM_TYPEMOUSE))) continue;

                const mouse = raw.data.mouse;

                const dx = mouse.lLastX;
                const dy = mouse.lLastY;

                event = .{ .relative_mouse_motion = .{ .dx = @floatFromInt(dx), .dy = @floatFromInt(dy) } };
            },
            win32.WM_SETCURSOR => _ = win32.SetCursor(@ptrCast(window.cursor)),

            // Key
            win32.WM_KEYDOWN, win32.WM_KEYUP => {
                const sym = DesktopWindow.Event.Key.Sym.fromWin32(std.enums.fromInt(win32.VIRTUAL_KEY, msg.wParam).?, msg.lParam) orelse continue;
                event = .{ .key = .{
                    .state = switch (msg.message) {
                        win32.WM_KEYDOWN => .pressed,
                        win32.WM_KEYUP => .released,
                        else => unreachable,
                    },
                    .code = @intCast((msg.lParam >> @intCast(16)) & 0xFF),
                    .sym = sym,
                } };
            },
            win32.WM_TOUCH => event = touch: {
                const c_inputs = win32.zig.loword(msg.wParam);
                var inputs: [10]win32.TOUCHINPUT = @splat(std.mem.zeroes(win32.TOUCHINPUT));
                if (win32.GetTouchInputInfo(@ptrFromInt(@as(usize, @intCast(msg.lParam))), c_inputs, &inputs, @sizeOf(win32.TOUCHINPUT)) == 1) {
                    defer _ = win32.CloseTouchInputHandle(@ptrFromInt(@as(usize, @intCast(msg.lParam))));
                    for (&inputs, 0..) |*input, i| {
                        const x = @as(f64, @floatFromInt(input.x)) / 100;
                        const y = @as(f64, @floatFromInt(input.y)) / 100;
                        const touch: DesktopWindow.Event.Touch = .{ .id = @intCast(i), .x = x, .y = y };

                        if (input.dwFlags.DOWN == 1) break :touch .{ .touch_down = touch };
                        if (input.dwFlags.UP == 1) break :touch .{ .touch_up = touch };
                        if (input.dwFlags.MOVE == 1) break :touch .{ .touch_motion = touch };
                    }
                }
                break :touch null;
            },
            else => {},
        }
    }

    return event;
}
fn windowSetProperty(userdata: ?*anyopaque, desktop_window: *DesktopWindow, property: DesktopWindow.Property) anyerror!void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    switch (property) {
        .title => |title| {
            const title_utf16 = try std.unicode.utf8ToUtf16LeAllocZ(self.gpa, title);
            defer self.gpa.free(title_utf16);
            _ = win32.SetWindowTextW(@ptrCast(window.hwnd), @ptrCast(title_utf16));
        },
        .size => |size| _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, 0, 0, @intCast(size.width), @intCast(size.height), .{ .NOZORDER = 1, .NOMOVE = 1 }),
        .position => |position| _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, position.x, position.y, 0, 0, .{ .NOZORDER = 1, .NOSIZE = 1 }),
        .resize_policy => |resize_policy| window.size_data.resize_policy = resize_policy,
        .mode => |mode| {
            _ = win32.ShowWindow(@ptrCast(window.hwnd), win32.SW_RESTORE);
            if (mode != .fullscreen and window.interface.mode == .fullscreen) {
                _ = win32.SetWindowLongW(@ptrCast(window.hwnd), win32.GWL_STYLE, window.previous_style);
                _ = win32.SetWindowPlacement(@ptrCast(window.hwnd), &window.previous_placement);
                _ = win32.SetWindowPos(@ptrCast(window.hwnd), null, 0, 0, 0, 0, .{ .DRAWFRAME = 1, .NOMOVE = 1, .NOSIZE = 1, .NOZORDER = 1, .NOOWNERZORDER = 1 });
            }
            switch (mode) {
                .windowed => {},
                .fullscreen => {
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
                },
                .maximized => _ = win32.ShowWindow(@ptrCast(window.hwnd), win32.SW_MAXIMIZE),
                .minimized => _ = win32.ShowWindow(@ptrCast(window.hwnd), win32.SW_MINIMIZE),
            }
        },
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
        .focused => {}, // TODO: add focus request
        .cursor => |cursor| {
            const idc = switch (cursor) {
                .arrow => win32.IDC_ARROW,
                .text => win32.IDC_IBEAM,
                .hand => win32.IDC_HAND,
                .grab => win32.IDC_HAND,
                .crosshair => win32.IDC_CROSS,
                .wait => win32.IDC_WAIT,
                .resize_ns => win32.IDC_SIZENS,
                .resize_ew => win32.IDC_SIZEWE,
                .resize_nesw => win32.IDC_SIZENESW,
                .resize_nwse => win32.IDC_SIZENWSE,
                .forbidden => win32.IDC_NO,
                .move => win32.IDC_SIZEALL,
                _ => return,
            };
            inline for (std.meta.fields(@TypeOf(self.cursors))) |field| {
                @field(self.cursors, field.name) = @ptrCast(win32.LoadCursorW(self.hinstance, idc));
            }

            //.arrow = @ptrCast(win32.LoadCursorW(instance, win32.IDC_ARROW)),
            //.text = @ptrCast(win32.LoadCursorW(instance, win32.IDC_IBEAM)),
            //.hand = @ptrCast(win32.LoadCursorW(instance, win32.IDC_HAND)),
            //.grab = @ptrCast(win32.LoadCursorW(instance, win32.IDC_HAND)), // fallback
            //.crosshair = @ptrCast(win32.LoadCursorW(instance, win32.IDC_CROSS)),
            //.wait = @ptrCast(win32.LoadCursorW(instance, win32.IDC_WAIT)),
            //.resize_ns = @ptrCast(win32.LoadCursorW(instance, win32.IDC_SIZENS)),
            //.resize_ew = @ptrCast(win32.LoadCursorW(instance, win32.IDC_SIZEWE)),
            //.resize_nesw = @ptrCast(win32.LoadCursorW(instance, win32.IDC_SIZENESW)),
            //.resize_nwse = @ptrCast(win32.LoadCursorW(instance, win32.IDC_SIZENWSE)),
            //.forbidden = @ptrCast(win32.LoadCursorW(instance, win32.IDC_NO)),
            //.move = @ptrCast(win32.LoadCursorW(instance, win32.IDC_SIZEALL)),
            //.grabbing = @ptrCast(win32.LoadCursorW(instance, win32.IDC_HAND)), // fallback
        },
        .cursor_mode => |mode| switch (mode) {
            .normal => {
                while (win32.ShowCursor(win32.TRUE) < 0) {}
                _ = win32.ClipCursor(null);
            },
            .hidden => {
                while (win32.ShowCursor(win32.FALSE) >= 0) {}
                _ = win32.ClipCursor(null);
            },
            .confined => {
                while (win32.ShowCursor(win32.TRUE) < 0) {}

                const rect = getClientScreenRect(@ptrCast(window.hwnd));
                _ = win32.ClipCursor(&rect);
            },
            .captured => {
                while (win32.ShowCursor(win32.FALSE) >= 0) {}

                const rect = getClientScreenRect(@ptrCast(window.hwnd));
                _ = win32.ClipCursor(&rect);
            },
            .locked => {
                while (win32.ShowCursor(win32.FALSE) >= 0) {}

                const rect = getClientScreenRect(@ptrCast(window.hwnd));
                _ = win32.ClipCursor(&rect);
            },
        },
    }
}
fn windowNative(userdata: ?*anyopaque, desktop_window: *DesktopWindow) DesktopWindow.Native {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    return .{
        .hinstance = self.hinstance,
        .hwnd = window.hwnd,
    };
}
fn windowFramebuffer(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!DesktopWindow.Framebuffer {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;

    std.log.info("no software rendering is currently not supported", .{});

    return undefined;
}
fn windowOpenglMakeCurrent(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    _ = self;

    const gl = window.surface.opengl;
    if (!win32.SUCCEEDED(win32.wglMakeCurrent(@ptrCast(gl.device_context), @ptrCast(gl.render_context)))) return reportErr(error.WglMakeCurrent);
}
fn windowOpenglSwapBuffers(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    _ = self;

    const gl = window.surface.opengl;
    if (!win32.SUCCEEDED(win32.SwapBuffers(@ptrCast(gl.device_context)))) return reportErr(error.WglSwapBuffers);
}
fn windowOpenglSwapInterval(userdata: ?*anyopaque, desktop_window: *DesktopWindow, interval: i32) anyerror!void {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    std.debug.assert(window.surface == .opengl);
    std.debug.assert(self.wglSwapIntervalEXT != null);

    if (!win32.SUCCEEDED(self.wglSwapIntervalEXT.?(interval))) return reportErr(error.WglMakeCurrent);
}
fn windowVulkanCreateSurface(userdata: ?*anyopaque, desktop_window: *DesktopWindow, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque {
    const self: *Win32 = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    const vkCreateWin32SurfaceKHR: vulkan.SurfaceCreateProc = @ptrCast(loader(instance, "vkCreateWin32SurfaceKHR") orelse return error.LoadVkCreateWin32SurfaceKHR);

    const create_info: vulkan.SurfaceCreateInfo = .{
        .hinstance = self.hinstance,
        .hwnd = window.hwnd,
    };

    var surface: ?*anyopaque = null;
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
        win32.WM_GETMINMAXINFO, win32.WM_SIZE, win32.WM_MOVE, win32.WM_SETFOCUS, win32.WM_KILLFOCUS, win32.WM_CLOSE => |wm| {
            if (!win32.SUCCEEDED(win32.PostMessageW(hwnd, win32.WM_USER + wm, wParam, lParam))) reportErr(error.PostMessage) catch {};
            return 0;
        },
        else => win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    };
}

fn getClientScreenRect(hwnd: win32.HWND) win32.RECT {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(hwnd, &rect);

    var min = win32.POINT{ .x = rect.left, .y = rect.top };
    var max = win32.POINT{ .x = rect.right, .y = rect.bottom };

    _ = win32.ClientToScreen(hwnd, &min);
    _ = win32.ClientToScreen(hwnd, &max);

    return .{
        .left = min.x,
        .top = min.y,
        .right = max.x,
        .bottom = max.y,
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
