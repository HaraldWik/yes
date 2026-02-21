const std = @import("std");
const win32 = @import("win32").everything;
const Platform = @import("../Platform.zig");
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

allocator: std.mem.Allocator,
instance: std.os.windows.HINSTANCE,

pub const Window = struct {
    interface: Platform.Window = .{},
    class: win32.WNDCLASSEXW = undefined,
    hwnd: std.os.windows.HWND = undefined,
    api: GraphicsApi = .none,

    previous_style: i32 = 0,
    previous_placement: win32.WINDOWPLACEMENT = std.mem.zeroInit(win32.WINDOWPLACEMENT, .{ .length = @sizeOf(win32.WINDOWPLACEMENT) }),

    pub const GraphicsApi = union(enum) {
        opengl: OpenGL,
        none: void,

        pub const OpenGL = struct {
            dc: win32.HDC = undefined, // Device context
            rc: win32.HGLRC = undefined, // Render context

            swapIntervalEXT: *const fn (i32) callconv(.winapi) win32.BOOL = undefined,
        };
    };
};

/// Alternativly you can use winMain and get the instane thru that
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
            .windowSetTitle = windowSetTitle,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.class = std.mem.zeroInit(win32.WNDCLASSEXW, .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .lpszClassName = win32.L("WindowClass"),
        .lpfnWndProc = wndProc,
        .hInstance = self.instance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .style = win32.WNDCLASS_STYLES{
            .OWNDC = if (window.api == .opengl) 1 else 0,
        },
    });
    if (!win32.SUCCEEDED(win32.RegisterClassExW(@ptrCast(&window.class)))) return error.RegisterClass;
    const title = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, options.title);

    window.hwnd = @ptrCast(win32.CreateWindowExW(
        .{ .TRANSPARENT = 1 },
        window.class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        @intCast(options.size.width),
        @intCast(options.size.height),
        null,
        null,
        self.instance,
        null,
    ) orelse return reportErr(error.CreateWindowFailed));

    self.allocator.free(title);

    if (window.api == .opengl) {
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

        _ = win32.ReleaseDC(@ptrCast(window.hwnd), dc);

        const getExtensionsStringARB: *const fn (win32.HDC) callconv(.winapi) ?[*:0]const u8 = @ptrCast(win32.wglGetProcAddress("wglGetExtensionsStringARB") orelse return error.WglGetProcAddress);

        var createContextAttribsARB: ?*const fn (win32.HDC, ?win32.HGLRC, [*:0]const i32) callconv(.winapi) ?win32.HGLRC = null;

        if (getExtensionsStringARB(dc)) |extensions| {
            var it = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
            while (it.next()) |name| {
                if (std.mem.eql(u8, name, "WGL_EXT_swap_control"))
                    window.api.opengl.swapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT") orelse return error.WglSwapIntervalEXT);
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
            WGL_CONTEXT_MAJOR_VERSION_ARB, @intCast(4),
            WGL_CONTEXT_MINOR_VERSION_ARB, @intCast(6),
            WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        };

        _ = win32.wglDeleteContext(rc);
        rc = try if (createContextAttribsARB) |createContextAttribs|
            createContextAttribs(dc, null, attributes) orelse return error.CreateModernOpenGL
        else
            error.NoCreateContextAttribs;
        _ = win32.wglMakeCurrent(dc, rc);
    }

    _ = win32.ShowWindow(@ptrCast(window.hwnd), .{ .SHOWNORMAL = 1 });
    if (!win32.SUCCEEDED(win32.UpdateWindow(@ptrCast(window.hwnd)))) return error.UpdateWindow;
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.api == .opengl) _ = win32.wglDeleteContext(window.api.opengl.rc);
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
        win32.WM_DESTROY => .close,
        win32.WM_SYSCOMMAND => switch (msg.wParam) {
            win32.SC_CLOSE => .close,
            else => {
                std.log.warn("unknown WM_SYSCOMMAND: {d}", .{msg.wParam});
                return null;
            },
        },
        win32.WM_USER + win32.WM_SETFOCUS => .{ .focus = .enter },
        win32.WM_USER + win32.WM_KILLFOCUS => .{ .focus = .leave },
        win32.WM_USER + win32.WM_SIZE => .{ .resize = .{
            .width = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam))))),
            .height = @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam >> 16))))),
        } },
        win32.WM_WINDOWPOSCHANGED => {
            std.debug.print("what\n", .{});
            return null;
        },
        // Mouse
        // win32.WM_MOUSEMOVE => .{ .mouse = .{ .move = .{
        //     .x = @intCast(@as(u16, @truncate(@as(usize, @intCast(msg.lParam))))),
        //     .y = @intCast(@as(u16, @truncate(@as(usize, @intCast(msg.lParam >> 16))))),
        // } } },
        // win32.WM_MOUSEWHEEL, win32.WM_MOUSEHWHEEL => {
        //     const delta: isize = @intCast((msg.wParam >> 16) & 0xFFFF);
        //     var lines: isize = @intCast(@divTrunc(delta, @as(isize, @intCast(win32.WHEEL_DELTA)))); // lines > 0 -> scroll right, lines < 0 -> left
        //     if (lines == 545) lines = -1;
        //     return .{ .mouse = .{
        //         .scroll = switch (msg.message) {
        //             win32.WM_MOUSEWHEEL => .{ .x = -lines },
        //             win32.WM_MOUSEHWHEEL => .{ .y = lines },
        //             else => unreachable,
        //         },
        //     } };
        // },
        // win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => |button| .{ .mouse = .{ .button = .{
        //     .state = switch (msg.message) {
        //         win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN => .pressed,
        //         win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP => .released,
        //         else => unreachable,
        //     },
        //     .code = Window.io.Event.Mouse.Button.Code.fromWin32(button, msg.wParam) orelse return null,
        //     .position = .{
        //         .x = @intCast(@as(u16, @truncate(@as(usize, @intCast(msg.lParam))))),
        //         .y = @intCast(@as(u16, @truncate(@as(usize, @intCast(msg.lParam >> 16))))),
        //     },
        // } } },

        // Key
        // win32.WM_KEYDOWN, win32.WM_KEYUP => {
        //     const sym = Window.io.Event.Key.Sym.fromWin32(std.enums.fromInt(win32.VIRTUAL_KEY, msg.wParam).?, msg.lParam) orelse return null;
        //     switch (msg.message) {
        //         win32.WM_KEYDOWN => {
        //             if (keyboard.keys[@intFromEnum(sym)] == .pressed) return null;
        //             keyboard.keys[@intFromEnum(sym)] = .pressed;
        //         },
        //         win32.WM_KEYUP => keyboard.keys[@intFromEnum(sym)] = .released,
        //         else => unreachable,
        //     }
        //     return .{ .key = .{
        //         .state = switch (msg.message) {
        //             win32.WM_KEYDOWN => .pressed,
        //             win32.WM_KEYUP => .released,
        //             else => unreachable,
        //         },
        //         .code = @intCast((msg.lParam >> @intCast(16)) & 0xFF),
        //         .sym = sym,
        //     } };
        // },
        else => null,
    };
}

fn windowSetTitle(context: *anyopaque, platform_window: *Platform.Window, title: []const u8) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const title_utf16 = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, title);
    defer self.allocator.free(title_utf16);
    _ = win32.SetWindowTextW(@ptrCast(window.hwnd), @ptrCast(title_utf16));
}

fn wndProc(hwnd: win32.HWND, msg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    return switch (msg) {
        win32.WM_SETFOCUS, win32.WM_KILLFOCUS => |focus| {
            if (!win32.SUCCEEDED(win32.PostMessageW(hwnd, win32.WM_USER + focus, wParam, lParam))) reportErr(error.PostMessage) catch {};
            return 0;
        },
        win32.WM_SIZE => {
            if (!win32.SUCCEEDED(win32.PostMessageW(hwnd, win32.WM_USER + win32.WM_SIZE, wParam, lParam))) reportErr(error.PostMessage) catch {};
            return 0;
        },
        else => win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    };
}

pub fn reportErr(err: anyerror) anyerror {
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
