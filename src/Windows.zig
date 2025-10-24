const std = @import("std");
const windows = std.os.windows;
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

instance: windows.HINSTANCE,
hwnd: windows.HWND,

var quit: bool = false;

pub fn open(config: @import("root.zig").Window.Config) !@This() {
    _ = MessageBoxA(null, "Windows support is very bad", "Warning", 0);

    const instance = GetModuleHandleW(null) orelse return error.GetInstanceHandle;

    var self: @This() = .{ .instance = instance, .hwnd = undefined };

    const class_name: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("WindowClass");

    var class: WNDCLASSEXW = .{
        .lpszClassName = class_name,
        .lpfnWndProc = handleMessages,
        .hInstance = instance,
    };

    _ = RegisterClassExW(&class);

    var title_buffer: [256]u16 = undefined;
    const title = title_buffer[0..(try std.unicode.utf8ToUtf16Le(&title_buffer, config.title[0 .. config.title.len + 1]))];

    const hwnd = CreateWindowExW(
        0,
        class_name,
        @ptrCast(title),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        @intCast(config.width),
        @intCast(config.height),
        null,
        null,
        instance,
        @ptrCast(&self),
    ) orelse return error.CreateWindowFailed;

    self.hwnd = hwnd;

    _ = ShowWindow(hwnd, SW_SHOWDEFAULT);
    _ = UpdateWindow(hwnd);

    return self;
}

pub fn close(self: @This()) void {
    _ = DestroyWindow(self.hwnd);
}

pub fn next(self: @This()) ?@import("root.zig").Event {
    _ = self;
    return if (quit) null else .none;
}

fn handleMessages(hwnd: windows.HWND, message: windows.UINT, w_param: usize, l_param: isize) callconv(.winapi) windows.LRESULT {
    switch (message) {
        WM_QUIT, WM_DESTROY => quit = true,
        else => return DefWindowProcW(hwnd, message, w_param, l_param),
    }
    return 0;
}

/// OLD
extern "user32" fn MessageBoxA(?windows.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

const WNDPROC = *const fn (hwnd: windows.HWND, uMsg: windows.UINT, wParam: usize, lParam: isize) callconv(.winapi) windows.LRESULT;

const WNDCLASSEXW = extern struct {
    cbSize: windows.UINT = @sizeOf(WNDCLASSEXW), // Must be initialized to the struct size
    style: windows.UINT = std.mem.zeroes(windows.UINT),
    lpfnWndProc: WNDPROC, // Pointer to the Window Procedure
    cbClsExtra: c_int = std.mem.zeroes(c_int), // Number of extra bytes to allocate
    cbWndExtra: c_int = std.mem.zeroes(c_int),
    hInstance: windows.HINSTANCE,
    hIcon: ?windows.HICON = null,
    hCursor: ?windows.HCURSOR = null,
    hbrBackground: ?windows.HBRUSH = null,
    lpszMenuName: ?windows.LPCWSTR = null,
    lpszClassName: windows.LPCWSTR, // The unique class name
    hIconSm: ?windows.HICON = null,
};

const POINT = extern struct {
    x: i32,
    y: i32,
};

const MSG = extern struct {
    hwnd: windows.HWND,
    message: windows.UINT,
    wParam: usize,
    lParam: isize,
    time: windows.DWORD,
    pt: POINT,
};

const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque, // The parameter passed in CreateWindowEx
    hInstance: windows.HINSTANCE,
    hMenu: ?*anyopaque,
    hwndParent: windows.HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: windows.DWORD,
    lpszName: windows.LPCWSTR,
    lpszClass: windows.LPCWSTR,
    dwExStyle: windows.DWORD,
};

extern "kernel32" fn GetModuleHandleW(lpModuleName: ?windows.LPCWSTR) callconv(.winapi) ?windows.HINSTANCE;

extern "user32" fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) callconv(.winapi) u16; // Returns an ATOM (u16) or 0 on failure

extern "user32" fn CreateWindowExW(
    dwExStyle: windows.DWORD,
    lpClassName: windows.LPCWSTR,
    lpWindowName: windows.LPCWSTR,
    dwStyle: windows.DWORD,
    x: u32,
    y: u32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?windows.HWND,
    hMenu: ?*anyopaque, // HMENU
    hInstance: windows.HINSTANCE,
    lpParam: ?*anyopaque, // LPVOID (used for 'self' pointer in WM_NCCREATE)
) callconv(.winapi) ?windows.HWND;

extern "user32" fn DefWindowProcW(
    hWnd: windows.HWND,
    Msg: windows.UINT,
    wParam: usize,
    lParam: isize,
) callconv(.winapi) windows.LRESULT;

extern "user32" fn ShowWindow(
    hWnd: windows.HWND,
    nCmdShow: i32,
) callconv(.winapi) i32; // Returns a BOOL (i32)

extern "user32" fn UpdateWindow(
    hWnd: windows.HWND,
) callconv(.winapi) i32; // Returns a BOOL (i32)

extern "user32" fn DestroyWindow(
    hWnd: windows.HWND,
) callconv(.winapi) i32; // Returns a BOOL (i32)

extern "user32" fn PeekMessageW(
    lpMsg: *MSG,
    hWnd: ?windows.HWND,
    wMsgFilterMin: windows.UINT,
    wMsgFilterMax: windows.UINT,
    wRemoveMsg: windows.UINT,
) callconv(.winapi) i32; // Returns BOOL (i32)

extern "user32" fn TranslateMessage(
    lpMsg: *const MSG,
) callconv(.winapi) i32; // Returns BOOL (i32)

extern "user32" fn DispatchMessageW(
    lpMsg: *const MSG,
) callconv(.winapi) isize; // Returns LRESULT (isize)

extern "user32" fn PostQuitMessage(
    nExitCode: i32,
) callconv(.winapi) void;

extern "user32" fn SetWindowLongPtrW(
    hWnd: windows.HWND,
    nIndex: i32,
    dwNewLong: windows.LONG_PTR,
) callconv(.winapi) windows.LONG_PTR;

extern "user32" fn GetWindowLongPtrW(
    hWnd: windows.HWND,
    nIndex: i32,
) callconv(.winapi) windows.LONG_PTR;

const WM_NCCREATE: windows.UINT = 0x0081;
const WM_CLOSE: windows.UINT = 0x0010;
const WM_DESTROY: windows.UINT = 0x0002;
const WM_QUIT: windows.UINT = 0x0012;

const GWLP_USERDATA: i32 = -21;
const GWLP_WNDPROC: i32 = -4;

const WS_OVERLAPPEDWINDOW: windows.DWORD = 0x00C00000 | 0x00080000 | 0x00040000 | 0x00020000 | 0x00010000 | 0x00000000;
const CW_USEDEFAULT: u32 = 0x80000000;

const PM_REMOVE: windows.UINT = 0x0001;
const SW_SHOWDEFAULT: i32 = 10;
