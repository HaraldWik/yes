const std = @import("std");
const root = @import("../root.zig");
const win32 = @import("../root.zig").native.win32.everything;
const Event = @import("../event.zig").Union;
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

instance: win32.HINSTANCE,
hwnd: win32.HWND,
api: GraphicsApi = .none,

pub const GraphicsApi = union(root.GraphicsApi) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: void,

    pub const OpenGL = struct {
        dc: win32.HDC,
        ctx: win32.HGLRC,

        wgl: Wgl,

        pub const Wgl = struct {
            swapIntervalEXT: *const fn (i32) callconv(.winapi) win32.BOOL,
            choosePixelFormatARB: *const fn (win32.HDC, ?[*]const i32, ?[*:0]const f32, u32, [*:0]i32, *u32) callconv(.winapi) win32.BOOL,
            createContextAttribsARB: *const fn (win32.HDC, ?win32.HGLRC, [*:0]const i32) callconv(.winapi) ?win32.HGLRC,
        };
    };
    pub const Vulkan = struct {
        instance: win32.HINSTANCE = undefined,
        getInstanceProcAddress: GetInstanceProcAddress,
        pub const GetInstanceProcAddress = *const fn (usize, [*:0]const u8) callconv(.winapi) ?*const fn () void;
    };
};

pub fn open(config: root.Window.Config) !@This() {
    const instance = win32.GetModuleHandleW(null) orelse return error.GetInstanceHandle;

    var class: win32.WNDCLASSEXW = std.mem.zeroInit(win32.WNDCLASSEXW, .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .lpszClassName = win32.L("WindowClass"),
        .lpfnWndProc = wndProc,
        .hInstance = instance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .style = win32.WNDCLASS_STYLES{
            .OWNDC = if (config.api == .opengl) 1 else 0,
        },
    });
    if (!win32.SUCCEEDED(win32.RegisterClassExW(@ptrCast(&class)))) return reportErr(error.RegisterClass);

    var title_buffer: [256]u16 = undefined;
    const title = title_buffer[0..(try std.unicode.utf8ToUtf16Le(&title_buffer, config.title[0 .. config.title.len + 1]))];

    const hwnd = win32.CreateWindowExW(
        .{},
        class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        @intCast(config.width),
        @intCast(config.height),
        null,
        null,
        instance,
        null,
    ) orelse return reportErr(error.CreateWindowFailed);

    const api: GraphicsApi = api: switch (config.api) {
        .opengl => {
            const dc = win32.GetDC(hwnd) orelse return error.GetDC;

            var pfd: win32.PIXELFORMATDESCRIPTOR = std.mem.zeroInit(win32.PIXELFORMATDESCRIPTOR, .{
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
                .iLayerType = win32.PFD_MAIN_PLANE,
            });

            const format = win32.ChoosePixelFormat(dc, &pfd);
            if (!win32.SUCCEEDED(format)) return reportErr(error.ChoosePixelFormat);
            if (!win32.SUCCEEDED(win32.SetPixelFormat(dc, format, &pfd))) return reportErr(error.SetPixelFormat);

            var ctx = win32.wglCreateContext(dc) orelse return reportErr(error.WglCreateContext);
            if (!win32.SUCCEEDED(win32.wglMakeCurrent(dc, ctx))) return reportErr(error.WglMakeCurrent);

            if (!win32.SUCCEEDED(win32.ReleaseDC(hwnd, dc))) return reportErr(error.WglReleaseDC);

            var wgl: GraphicsApi.OpenGL.Wgl = undefined;
            const getExtensionsStringARB_ptr = win32.wglGetProcAddress("wglGetExtensionsStringARB") orelse return reportErr(error.WglGetProcAddress);
            const getExtensionsStringARB: *const fn (win32.HDC) callconv(.winapi) ?[*:0]const u8 = @ptrCast(getExtensionsStringARB_ptr);

            if (getExtensionsStringARB(dc)) |extensions| {
                var it = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (it.next()) |name| {
                    const ext = std.meta.stringToEnum(enum {
                        WGL_EXT_swap_control,
                        WGL_ARB_pixel_format,
                        WGL_ARB_create_context_profile,
                    }, name) orelse continue;
                    switch (ext) {
                        .WGL_EXT_swap_control => wgl.swapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT") orelse return error.WglSwapIntervalEXT),
                        .WGL_ARB_pixel_format => wgl.choosePixelFormatARB = @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB") orelse return error.WglChoosePixelFormatARB),
                        .WGL_ARB_create_context_profile => wgl.createContextAttribsARB = @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB") orelse return error.WglCreateContextAttribsARB),
                    }
                }
            }

            const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
            const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
            const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
            const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;

            const attribs = [_:0]i32{
                WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
                WGL_CONTEXT_MINOR_VERSION_ARB, 5,
                WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                0,
            };

            const ctx_ = wgl.createContextAttribsARB(dc, null, &attribs) orelse return reportErr(error.CreateModernOpenGL);
            _ = win32.wglMakeCurrent(dc, ctx_);
            _ = win32.wglDeleteContext(ctx_);
            ctx = ctx;

            break :api .{ .opengl = .{
                .dc = dc,
                .ctx = ctx,
                .wgl = wgl,
            } };
        },
        .vulkan => {
            const vulkan: win32.HINSTANCE = win32.LoadLibraryW(win32.L("vulkan-1.dll")) orelse return reportErr(error.LoadLibraryWVulkan);
            const getInstanceProcAddress: GraphicsApi.Vulkan.GetInstanceProcAddress = @ptrCast(win32.GetProcAddress(vulkan, "vkGetInstanceProcAddr") orelse return error.GetProcAddress);
            break :api .{ .vulkan = .{
                .instance = vulkan,
                .getInstanceProcAddress = getInstanceProcAddress,
            } };
        },
        .none => .{ .none = undefined },
    };

    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    if (!win32.SUCCEEDED(win32.UpdateWindow(hwnd))) return reportErr(error.UpdateWindow);

    return .{
        .instance = instance,
        .hwnd = hwnd,
        .api = api,
    };
}

pub fn close(self: @This()) void {
    switch (self.api) {
        .opengl => {
            _ = win32.wglDeleteContext(self.api.opengl.ctx);
        },
        .vulkan => _ = win32.FreeLibrary(self.api.vulkan.instance),
        .none => {},
    }
    _ = win32.DestroyWindow(self.hwnd);
}

pub fn poll(self: @This()) !?Event {
    var msg: win32.MSG = undefined;
    if (win32.PeekMessageW(&msg, self.hwnd, 0, 0, .{ .REMOVE = 1 }) == 0) return null;
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
        win32.WM_SIZE, win32.WM_USER + 1 => .{ .resize = .{
            @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam))))),
            @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam >> 16))))),
        } },
        win32.WM_WINDOWPOSCHANGED => {
            std.debug.print("what\n", .{});
            return null;
        },
        win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN => |button| .{ .mouse = .{
            .right = button == win32.WM_RBUTTONDOWN,
            .middle = button == win32.WM_MBUTTONDOWN,
            .left = button == win32.WM_LBUTTONDOWN,
            .forward = button == win32.WM_XBUTTONDOWN and ((msg.wParam >> 16) & 0xFFFF) == @as(u32, @bitCast(win32.XBUTTON1)),
            .backward = button == win32.WM_XBUTTONDOWN and ((msg.wParam >> 16) & 0xFFFF) == @as(u32, @bitCast(win32.XBUTTON2)),
        } },
        win32.WM_KEYDOWN => .{ .key_down = Event.Key.fromWin32(std.enums.fromInt(win32.VIRTUAL_KEY, msg.wParam).?, msg.lParam) orelse return null },
        win32.WM_KEYUP => .{ .key_up = Event.Key.fromWin32(std.enums.fromInt(win32.VIRTUAL_KEY, msg.wParam).?, msg.lParam) orelse return null },
        else => null,
    };
}

pub fn getSize(self: @This()) [2]usize {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(self.hwnd, &rect);
    return .{ @intCast(rect.right - rect.left), @intCast(rect.bottom - rect.top) };
}

pub fn wndProc(hwnd: win32.HWND, msg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    return switch (msg) {
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            _ = win32.MessageBoxA(hwnd, "Hello", "Title", .{});
            return 0;
        },
        win32.WM_SIZE => {
            if (!win32.SUCCEEDED(win32.PostMessageW(hwnd, win32.WM_USER + 1, wParam, lParam))) reportErr(error.PostMessage) catch {};
            return 0;
        },
        else => win32.DefWindowProcW(hwnd, msg, wParam, lParam),
    };
}

pub fn reportErr(err: anyerror) anyerror {
    const code = win32.GetLastError();

    var buf: [512:0]u16 = undefined;
    const len = win32.FormatMessageW(
        .{ .FROM_SYSTEM = 1, .IGNORE_INSERTS = 1 },
        null,
        @intFromEnum(code),
        0,
        @ptrCast(&buf),
        buf.len,
        null,
    );

    _ = win32.MessageBoxW(
        null,
        @ptrCast(buf[0..len]),
        win32.L("Error"),
        .{ .ICONHAND = 1 },
    );

    return err;
}
