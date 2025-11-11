const std = @import("std");
const root = @import("root.zig");
const win32 = @import("root.zig").native.win32.everything;
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

const c = @cImport(@cInclude("GL/gl.h"));

instance: win32.HINSTANCE,
hwnd: win32.HWND,
api: GraphicsApi = .none,

pub const GraphicsApi = union(root.GraphicsApi) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: void,

    pub const OpenGL = struct {
        dc: win32.HDC,
        glrc: win32.HGLRC,

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
        .lpfnWndProc = win32.DefWindowProcW,
        .hInstance = instance,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .style = win32.WNDCLASS_STYLES{
            .OWNDC = if (config.api == .opengl) 1 else 0,
        },
    });
    _ = win32.RegisterClassExW(@ptrCast(&class));

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
    ) orelse return error.CreateWindowFailed;

    const api: GraphicsApi = switch (config.api) {
        .opengl => opengl: {
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

            const pf = win32.ChoosePixelFormat(dc, &pfd);
            if (pf == 0) return error.ChoosePixelFormat;
            if (!win32.SUCCEEDED(win32.SetPixelFormat(dc, pf, &pfd))) return error.SetPixelFormat;

            var glrc = win32.wglCreateContext(dc) orelse return error.WglCreateContext;
            if (!win32.SUCCEEDED(win32.wglMakeCurrent(dc, glrc))) return error.WglMakeCurrent;

            var wgl: GraphicsApi.OpenGL.Wgl = undefined;
            const getExtensionsStringARB_ptr = win32.wglGetProcAddress("wglGetExtensionsStringARB") orelse return error.WglGetProcAddress;
            const getExtensionsStringARB: *const fn (win32.HDC) callconv(.winapi) ?[*:0]const u8 = @ptrCast(getExtensionsStringARB_ptr);

            if (getExtensionsStringARB(dc)) |extensions| {
                var it = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (it.next()) |name| {
                    if (std.mem.eql(u8, name, "WGL_EXT_swap_control"))
                        wgl.swapIntervalEXT = @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT"))
                    else if (std.mem.eql(u8, name, "WGL_ARB_pixel_format"))
                        wgl.choosePixelFormatARB = @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB"))
                    else if (std.mem.eql(u8, name, "WGL_ARB_create_context_profile"))
                        wgl.createContextAttribsARB = @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB"));
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

            const ctx = wgl.createContextAttribsARB(dc, null, &attribs) orelse return error.CreateModernOpenGL;
            _ = win32.wglMakeCurrent(dc, ctx);
            _ = win32.wglDeleteContext(glrc);
            glrc = ctx;

            break :opengl .{ .opengl = .{
                .dc = dc,
                .glrc = glrc,
                .wgl = wgl,
            } };
        },
        .vulkan => vulkan: {
            const vulkan: win32.HINSTANCE = win32.LoadLibraryW(win32.L("vulkan-1.dll")) orelse return error.LoadLibraryWVulkan;
            const getInstanceProcAddress: GraphicsApi.Vulkan.GetInstanceProcAddress = @ptrCast(win32.GetProcAddress(vulkan, "vkGetInstanceProcAddr") orelse return error.GetProcAddress);
            break :vulkan .{ .vulkan = .{
                .instance = vulkan,
                .getInstanceProcAddress = getInstanceProcAddress,
            } };
        },
        .none => .{ .none = undefined },
    };

    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    if (!win32.SUCCEEDED(win32.UpdateWindow(hwnd))) return error.UpdateWindow;

    return .{
        .instance = instance,
        .hwnd = hwnd,
        .api = api,
    };
}

pub fn close(self: @This()) void {
    switch (self.api) {
        .opengl => {
            _ = win32.wglDeleteContext(self.api.opengl.glrc);
            _ = win32.ReleaseDC(self.hwnd, self.api.opengl.dc);
        },
        .vulkan => _ = win32.FreeLibrary(self.api.vulkan.instance),
        .none => {},
    }
    _ = win32.DestroyWindow(self.hwnd);
}

pub fn poll(self: @This()) !?root.Event {
    var msg: win32.MSG = undefined;
    if (win32.PeekMessageW(&msg, self.hwnd, 0, 0, .{ .REMOVE = 1 }) == 0) return null;
    _ = win32.TranslateMessage(&msg);
    _ = win32.DispatchMessageW(&msg);

    return switch (msg.message) {
        win32.WM_DESTROY => .close,
        win32.WM_SYSCOMMAND => switch (msg.wParam) {
            win32.SC_CLOSE => .close,
            // win32.SC_MAXIMIZE => null,
            else => {
                std.debug.print("unknown WM_SYSCOMMAND: {d}\n", .{msg.wParam});
                return null;
            },
        },
        win32.WM_SIZE => .{ .resize = .{
            @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam))))),
            @intCast(@as(u16, @truncate(@as(u32, @intCast(msg.lParam >> 16))))),
        } },
        win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN => |button| .{ .mouse = .{
            .right = button == win32.WM_RBUTTONDOWN,
            .middle = button == win32.WM_MBUTTONDOWN,
            .left = button == win32.WM_LBUTTONDOWN,
            .forward = button == win32.WM_XBUTTONDOWN and ((msg.wParam >> 16) & 0xFFFF) == @as(u32, @bitCast(win32.XBUTTON1)),
            .backward = button == win32.WM_XBUTTONDOWN and ((msg.wParam >> 16) & 0xFFFF) == @as(u32, @bitCast(win32.XBUTTON2)),
        } },

        else => return null,
    };
}

pub fn getSize(self: @This()) [2]usize {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(self.hwnd, &rect);
    return .{ @intCast(rect.right - rect.left), @intCast(rect.bottom - rect.top) };
}

pub fn isKeyDown(self: @This(), key: root.Key) bool {
    _ = self;
    const virtual_key: win32.VIRTUAL_KEY = virtualKeyFromKey(key);
    const state = win32.GetAsyncKeyState(@intCast(@intFromEnum(virtual_key)));
    return (state & @as(i16, @bitCast(@as(u16, 0x8000)))) != 0;
}

fn getLastError() ?anyerror {
    const err = win32.GetLastError();
    if (err == .NO_ERROR) return null;
    std.log.err("win32: {s}", @tagName(win32.GetLastError()));
    return error.Win32;
}

pub fn virtualKeyFromKey(key: root.Key) win32.VIRTUAL_KEY {
    return switch (key) {
        // Control keys
        .backspace => win32.VK_BACK,
        .tab => win32.VK_TAB,
        .clear => win32.VK_CLEAR,
        .enter => win32.VK_RETURN,
        .escape => win32.VK_ESCAPE,
        .delete => win32.VK_DELETE,

        // Modifiers
        .left_shift => win32.VK_LSHIFT,
        .right_shift => win32.VK_RSHIFT,
        .left_ctrl => win32.VK_LCONTROL,
        .right_ctrl => win32.VK_RCONTROL,
        .left_alt => win32.VK_LMENU,
        .right_alt => win32.VK_RMENU,
        .left_super => win32.VK_LWIN, // Windows / Command key
        .right_super => win32.VK_RWIN,
        .caps_lock => win32.VK_NUMLOCK,

        // Navigation
        .up => win32.VK_UP,
        .down => win32.VK_DOWN,
        .left => win32.VK_LEFT,
        .right => win32.VK_RIGHT,
        .home => win32.VK_HOME,
        .end => win32.VK_END,
        .page_up => win32.VK_PRIOR,
        .page_down => win32.VK_NEXT,
        .insert => win32.VK_INSERT,

        // Function keys
        .f1 => win32.VK_F1,
        .f2 => win32.VK_F2,
        .f3 => win32.VK_F3,
        .f4 => win32.VK_F4,
        .f5 => win32.VK_F5,
        .f6 => win32.VK_F6,
        .f7 => win32.VK_F7,
        .f8 => win32.VK_F8,
        .f9 => win32.VK_F9,
        .f10 => win32.VK_F10,
        .f11 => win32.VK_F11,
        .f12 => win32.VK_F12,

        // Numpad
        .numpad_0 => win32.VK_NUMPAD0,
        .numpad_1 => win32.VK_NUMPAD1,
        .numpad_2 => win32.VK_NUMPAD2,
        .numpad_3 => win32.VK_NUMPAD3,
        .numpad_4 => win32.VK_NUMPAD4,
        .numpad_5 => win32.VK_NUMPAD5,
        .numpad_6 => win32.VK_NUMPAD6,
        .numpad_7 => win32.VK_NUMPAD7,
        .numpad_8 => win32.VK_NUMPAD8,
        .numpad_9 => win32.VK_NUMPAD9,
        .numpad_add => win32.VK_ADD,
        .numpad_subtract => win32.VK_SUBTRACT,
        .numpad_multiply => win32.VK_MULTIPLY,
        .numpad_divide => win32.VK_DIVIDE,
        .numpad_enter => win32.VK_RETURN,
        .numpad_decimal => win32.VK_DECIMAL,
        else => @enumFromInt(@as(u16, @intCast(@intFromEnum(key)))),
    };
}
