const std = @import("std");
const opengl = @import("../opengl.zig");
const vulkan = @import("../root.zig").vulkan;
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");
const xcb = @import("xcb");
const xkb = @import("xkbcommon");

gpa: std.mem.Allocator,
connection: *xcb.xcb_connection_t,
screen: *xcb.xcb_screen_t,
screen_index: u32,
atom_table: AtomTable,
extensions: struct {
    xinput_opcode: ?u8 = null,
} = .{},
windows: std.ArrayList(?*Window) = .empty,
keyboard: Keyboard,

pub const AtomTable = struct {
    utf8_string: xcb.xcb_atom_t,
    wm: struct {
        protocols: xcb.xcb_atom_t,
    },
    net_wm: struct {
        name: xcb.xcb_atom_t,
        state: xcb.xcb_atom_t,
        state_fullscreen: xcb.xcb_atom_t,
        state_maximized_horz: xcb.xcb_atom_t,
        state_maximized_vert: xcb.xcb_atom_t,
        state_above: xcb.xcb_atom_t,
        active_window: xcb.xcb_atom_t,
    },
    motif_wm_hints: xcb.xcb_atom_t,

    pub fn load(connection: *xcb.xcb_connection_t) @This() {
        const utf8_string_cookie = cookie(connection, "UTF8_STRING");
        const wm_protocols_cookie = cookie(connection, "WM_PROTOCOLS");
        const net_wm_name_cookie = cookie(connection, "_NET_WM_NAME");
        const net_wm_state_cookie = cookie(connection, "_NET_WM_STATE");
        const net_wm_state_fullscreen_cookie = cookie(connection, "_NET_WM_STATE_FULLSCREEN");
        const net_wm_state_maximized_horz_cookie = cookie(connection, "_NET_WM_STATE_MAXIMIZED_HORZ");
        const net_wm_state_maximized_vert_cookie = cookie(connection, "_NET_WM_STATE_MAXIMIZED_VERT");
        const net_wm_state_above_cookie = cookie(connection, "_NET_WM_STATE_ABOVE");
        const motif_wm_hints_cookie = cookie(connection, "_MOTIF_WM_HINTS");
        const net_wm_active_window_cookie = cookie(connection, "_NET_ACTIVE_WINDOW");

        return .{
            .utf8_string = atom(connection, utf8_string_cookie),
            .wm = .{
                .protocols = atom(connection, wm_protocols_cookie),
            },
            .net_wm = .{
                .name = atom(connection, net_wm_name_cookie),
                .state = atom(connection, net_wm_state_cookie),
                .state_fullscreen = atom(connection, net_wm_state_fullscreen_cookie),
                .state_maximized_horz = atom(connection, net_wm_state_maximized_horz_cookie),
                .state_maximized_vert = atom(connection, net_wm_state_maximized_vert_cookie),
                .state_above = atom(connection, net_wm_state_above_cookie),
                .active_window = atom(connection, net_wm_active_window_cookie),
            },
            .motif_wm_hints = atom(connection, motif_wm_hints_cookie),
        };
    }

    fn cookie(connection: *xcb.xcb_connection_t, name: []const u8) xcb.xcb_intern_atom_cookie_t {
        return xcb.xcb_intern_atom(connection, 0, @intCast(name.len), name.ptr);
    }

    fn atom(connection: *xcb.xcb_connection_t, c: xcb.xcb_intern_atom_cookie_t) xcb.xcb_atom_t {
        return xcb.xcb_intern_atom_reply(connection, c, null).?.*.atom;
    }
};

pub const Keyboard = struct {
    context: *xkb.xkb_context,
    keymap: *xkb.xkb_keymap,
    state: *xkb.xkb_state,
};

pub const Window = struct {
    interface: PlatformWindow = .{},
    id: xcb.xcb_window_t = 0,
    event_queue: std.ArrayList(PlatformWindow.Event) = .empty,
    wm_delete_atom: xcb.xcb_atom_t = 0,
    surface: union {
        empty: void,
        framebuffer: Framebuffer,
        glx: struct {
            context: xcb.xcb_glx_context_t,
        },
    } = .{ .empty = {} },
};

pub fn init(gpa: std.mem.Allocator, minimal: std.process.Init.Minimal) !@This() {
    var screen_index: c_int = 0;
    const display_name = minimal.environ.getPosix("DISPLAY");
    const connection = xcb.xcb_connect(@ptrCast(display_name), &screen_index) orelse return error.Connect;

    const setup = xcb.xcb_get_setup(connection);
    var screen_it = xcb.xcb_setup_roots_iterator(setup);
    for (0..@intCast(screen_index)) |_| xcb.xcb_screen_next(&screen_it);
    const screen: *xcb.xcb_screen_t = screen_it.data orelse return error.XcbUnsupported;

    _ = xcb.xcb_change_keyboard_control(connection, xcb.XCB_KB_AUTO_REPEAT_MODE, &@as(u32, 0));

    const xinput = xcb.xcb_get_extension_data(connection, &xcb.xcb_input_id);

    var keyboard: Keyboard = undefined;
    keyboard.context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS) orelse return error.CreateKeyboardContext;
    keyboard.keymap = xkb.xkb_keymap_new_from_names(keyboard.context, null, xkb.XKB_KEYMAP_COMPILE_NO_FLAGS) orelse return error.CreateDefaultKeymap;
    keyboard.state = xkb.xkb_state_new(keyboard.keymap) orelse return error.CreateKeyboardState;

    return .{
        .gpa = gpa,
        .connection = connection,
        .screen = screen,
        .screen_index = @intCast(screen_index),
        .atom_table = .load(connection),
        .extensions = .{
            .xinput_opcode = if (xinput.*.present == 1) xinput.*.major_opcode else null,
        },
        .keyboard = keyboard,
    };
}

pub fn deinit(self: *@This()) void {
    xkb.xkb_state_unref(self.keyboard.state);
    xkb.xkb_keymap_unref(self.keyboard.keymap);
    xkb.xkb_context_unref(self.keyboard.context);
    self.windows.deinit(self.gpa);
    xcb.xcb_disconnect(self.connection);
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = opengl.glXGetProcAddress,
        },
    };
}

pub fn windowFromId(self: *@This(), id: xcb.xcb_window_t) ?struct { *Window, usize } {
    for (self.windows.items, 0..) |window, index| {
        if (window == null) continue;
        if (window.?.id == id) return .{ window.?, index };
    } else return null;
}

fn xiSetMask(mask: []u8, event: u16) void {
    mask[event / 8] |= @as(u8, 1) << @intCast(event % 8);
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    for (self.windows.items, 0..) |other_window, index| {
        if (other_window != null) continue;
        self.windows.items[index] = window;
    } else try self.windows.append(self.gpa, window);

    window.id = xcb.xcb_generate_id(self.connection);

    var fb_config: xcb.xcb_glx_fbconfig_t = 0;

    const visual: xcb.xcb_visualid_t = switch (options.surface_type) {
        .empty => self.screen.root_visual,
        .framebuffer => visual: {
            var depth_iter = xcb.xcb_screen_allowed_depths_iterator(self.screen);
            while (depth_iter.rem > 0) : (xcb.xcb_depth_next(&depth_iter)) {
                const depth: *xcb.xcb_depth_t = depth_iter.data.?;
                if (depth.depth != 32) continue;

                var visual_iter = xcb.xcb_depth_visuals_iterator(depth);
                while (visual_iter.rem > 0) : (xcb.xcb_visualtype_next(&visual_iter)) {
                    const visual: *xcb.xcb_visualtype_t = visual_iter.data.?;
                    if (visual.bits_per_rgb_value != 8) continue;
                    break :visual visual.visual_id;
                }
            }
            return error.NoVisualWithFramebufferSupports;
        },
        .opengl => visual: {
            const cookie = xcb.xcb_glx_get_fb_configs(self.connection, self.screen_index);
            const configs_reply: *xcb.xcb_glx_get_fb_configs_reply_t =
                xcb.xcb_glx_get_fb_configs_reply(self.connection, cookie, null) orelse return error.NoFBConfigs;

            const num_configs = configs_reply.*.num_FB_configs;
            const num_props = configs_reply.*.num_properties;

            const properties = xcb.xcb_glx_get_fb_configs_property_list(configs_reply)[0..@intCast(xcb.xcb_glx_get_fb_configs_property_list_length(configs_reply))];

            var chosen_visual_id: u32 = 0;

            var i: usize = 0;
            while (i < num_configs) : (i += 1) {
                const base = i * num_props;
                const fbconfig_id = properties[base]; // first element is FBConfig ID
                const config_props = properties[base + 1 .. base + num_props];

                var j: usize = 0;
                var good = true;
                var visual_id: u32 = 0;

                while (j + 1 < config_props.len) : (j += 2) {
                    const attr = config_props[j];
                    const val = config_props[j + 1];

                    if (attr == 0) visual_id = val else // XCB_GLX_VISUAL_ID
                    if (attr == 5 and val == 0) good = false else // GLX_DOUBLEBUFFER
                    if (attr == 8 and val < 8) good = false else // GLX_RED_SIZE
                    if (attr == 9 and val < 8) good = false else // GLX_GREEN_SIZE
                    if (attr == 10 and val < 8) good = false else // GLX_BLUE_SIZE
                    if (attr == 11 and val < 8) good = false else // GLX_ALPHA_SIZE
                    if (attr == 12 and val < 24) good = false; // GLX_DEPTH_SIZE
                }

                if (good) {
                    fb_config = fbconfig_id; // store FBConfig for later GLX context
                    chosen_visual_id = visual_id; // store visual ID for XCB window
                    break;
                }
            }

            break :visual @intCast(chosen_visual_id);
        },
        .vulkan => self.screen.root_visual,
    };

    const mask: u32 = xcb.XCB_CW_EVENT_MASK;
    const values = [_]u32{
        0 |
            xcb.XCB_EVENT_MASK_STRUCTURE_NOTIFY |
            xcb.XCB_EVENT_MASK_EXPOSURE |
            xcb.XCB_EVENT_MASK_FOCUS_CHANGE |
            xcb.XCB_EVENT_MASK_KEYMAP_STATE |
            xcb.XCB_EVENT_MASK_KEY_PRESS |
            xcb.XCB_EVENT_MASK_KEY_RELEASE |
            xcb.XCB_EVENT_MASK_POINTER_MOTION |
            xcb.XCB_EVENT_MASK_BUTTON_PRESS |
            xcb.XCB_EVENT_MASK_BUTTON_RELEASE,
    };

    _ = xcb.xcb_create_window(
        self.connection,
        if (options.surface_type == .framebuffer) 32 else xcb.XCB_COPY_FROM_PARENT,
        window.id,
        self.screen.root,
        if (options.position) |position| @intCast(position.x) else 0,
        if (options.position) |position| @intCast(position.y) else 0,
        @intCast(options.size.width),
        @intCast(options.size.height),
        0,
        xcb.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        visual,
        mask,
        &values,
    );

    if (self.extensions.xinput_opcode) |_| {
        var mask_bytes: [4]u8 = @splat(0);

        xiSetMask(&mask_bytes, xcb.XCB_INPUT_MOTION);
        xiSetMask(&mask_bytes, xcb.XCB_INPUT_BUTTON_PRESS);
        xiSetMask(&mask_bytes, xcb.XCB_INPUT_BUTTON_RELEASE);
        xiSetMask(&mask_bytes, xcb.XCB_INPUT_TOUCH_BEGIN);
        xiSetMask(&mask_bytes, xcb.XCB_INPUT_TOUCH_END);
        xiSetMask(&mask_bytes, xcb.XCB_INPUT_TOUCH_UPDATE);

        const total_size = @sizeOf(xcb.xcb_input_event_mask_t) + mask_bytes.len;

        var buffer: [total_size]u8 = undefined;

        const evmask: *xcb.xcb_input_event_mask_t = @ptrCast(@alignCast(&buffer));
        evmask.* = .{
            .deviceid = xcb.XCB_INPUT_DEVICE_ALL_MASTER,
            .mask_len = mask_bytes.len,
        };

        const mask_ptr: [*]u8 = @ptrCast(&buffer[@sizeOf(xcb.xcb_input_event_mask_t)]);
        @memcpy(mask_ptr[0..mask_bytes.len], mask_bytes[0..]);

        _ = xcb.xcb_input_xi_select_events(self.connection, window.id, 1, evmask);
    }

    _ = xcb.xcb_map_window(self.connection, window.id);

    window.wm_delete_atom = xcb.xcb_intern_atom_reply(
        self.connection,
        xcb.xcb_intern_atom(self.connection, 0, "WM_DELETE_WINDOW".len, "WM_DELETE_WINDOW"),
        null,
    ).?.*.atom;

    // Tell X server that we want to receive WM_DELETE_WINDOW events
    _ = xcb.xcb_change_property(
        self.connection,
        xcb.XCB_PROP_MODE_REPLACE,
        window.id,
        self.atom_table.wm.protocols,
        4, // XA_ATOM = 4
        32,
        1,
        &window.wm_delete_atom,
    );

    try windowSetProperty(context, platform_window, .{ .title = options.title });

    try windowSetProperty(context, platform_window, .{ .resize_policy = options.resize_policy });
    if (options.fullscreen) try windowSetProperty(context, platform_window, .{ .fullscreen = options.fullscreen });
    if (options.maximized) try windowSetProperty(context, platform_window, .{ .maximized = options.maximized });
    if (options.minimized) try windowSetProperty(context, platform_window, .{ .minimized = options.minimized });
    if (!options.focused) try windowSetProperty(context, platform_window, .{ .focused = options.focused });
    if (options.always_on_top) try windowSetProperty(context, platform_window, .{ .always_on_top = options.always_on_top });
    if (options.floating) |floating| try windowSetProperty(context, platform_window, .{ .floating = floating });
    if (!options.decorated) try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });

    switch (options.surface_type) {
        .empty => {},
        .framebuffer => {
            window.surface = .{ .framebuffer = try .init(self.connection) };
        },
        .opengl => {
            const context_id: xcb.xcb_glx_context_t = xcb.xcb_generate_id(self.connection);

            const cookie: xcb.xcb_void_cookie_t = .{
                .sequence = xcb.xcb_glx_make_current(
                    self.connection,
                    window.id,
                    context_id,
                    0, // old_context_tag
                ).sequence,
            };

            if (xcb.xcb_request_check(self.connection, cookie) != null) return error.MakeCurrentFailed;

            window.surface = .{ .glx = .{ .context = context_id } };
        },
        .vulkan => {},
    }

    try window.event_queue.append(self.gpa, .{ .resize = options.size });
}
fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _, const window_index = self.windowFromId(window.id).?;
    self.windows.items[window_index] = null;

    window.event_queue.deinit(self.gpa);
    _ = xcb.xcb_destroy_window(self.connection, window.id);
}
fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.event_queue.pop()) |event| return event;

    var out_event: ?PlatformWindow.Event = null;
    var target_id: xcb.xcb_window_t = 0;

    const generic_event: *xcb.xcb_generic_event_t = xcb.xcb_poll_for_event(self.connection) orelse return null;
    defer std.heap.c_allocator.destroy(generic_event);
    const event_type = generic_event.*.response_type & 0x7f;
    switch (event_type) {
        xcb.XCB_CLIENT_MESSAGE => {
            const event: *xcb.xcb_client_message_event_t = @ptrCast(generic_event);
            target_id = event.window;

            const target, _ = self.windowFromId(event.window).?;
            if (event.data.data32[0] == target.wm_delete_atom) {
                out_event = .close;
            }
        },

        xcb.XCB_CONFIGURE_NOTIFY => {
            const event: *xcb.xcb_configure_notify_event_t = @ptrCast(generic_event);
            target_id = event.window;
            const target, _ = self.windowFromId(target_id).?;

            const translate: *xcb.xcb_translate_coordinates_reply_t =
                xcb.xcb_translate_coordinates_reply(self.connection, xcb.xcb_translate_coordinates(self.connection, event.window, self.screen.root, @intCast(event.x), @intCast(event.y)), null).?;

            const size: PlatformWindow.Size = .{ .width = @intCast(event.width), .height = @intCast(event.height) };
            const position: PlatformWindow.Position = .{ .x = @intCast(translate.dst_x), .y = @intCast(translate.dst_y) };

            if (position.x != target.interface.position.x or
                position.y != target.interface.position.y)
            {
                out_event = .{ .move = position };
            }

            switch (target.interface.surface_type) {
                .empty => if (!size.eql(target.interface.size)) try target.event_queue.append(self.gpa, .{ .resize = size }),
                .framebuffer => if (!size.eql(target.interface.size)) {
                    try target.event_queue.append(self.gpa, .{ .resize = size });

                    if (target.interface.surface_type == .framebuffer) {
                        try target.surface.framebuffer.resize(self.connection, target.id, size);
                    }
                },
                .opengl, .vulkan => {},
            }
        },
        xcb.XCB_EXPOSE => {
            const event: *xcb.xcb_expose_event_t = @ptrCast(generic_event);
            target_id = event.window;
            const target, _ = self.windowFromId(target_id).?;

            const size: PlatformWindow.Size = .{ .width = @intCast(event.width), .height = @intCast(event.height) };
            if (target.interface.surface_type == .vulkan or target.interface.surface_type == .opengl) out_event = .{ .resize = size };

            if (target.interface.surface_type == .framebuffer) {
                _ = xcb.xcb_render_composite(self.connection, xcb.XCB_RENDER_PICT_OP_OVER, target.surface.framebuffer.picture, 0, target.surface.framebuffer.picture, 0, 0, 0, 0, 0, 0, @intCast(size.width), @intCast(size.height));
                _ = xcb.xcb_flush(self.connection);
            }
        },

        xcb.XCB_FOCUS_IN => {
            const event: *xcb.xcb_focus_in_event_t = @ptrCast(generic_event);
            target_id = event.event;
            out_event = .{ .focus = true };
        },
        xcb.XCB_FOCUS_OUT => {
            const event: *xcb.xcb_focus_out_event_t = @ptrCast(generic_event);
            target_id = event.event;
            out_event = .{ .focus = false };
        },

        xcb.XCB_KEYMAP_NOTIFY => {
            const event: *xcb.xcb_keymap_notify_event_t = @ptrCast(generic_event);

            for (event.keys, 0..) |byte, i| {
                for (0..8) |bit| {
                    const pressed = (byte >> @intCast(bit)) & 1;
                    const keycode: u8 = @intCast(i * 8 + bit);
                    _ = xkb.xkb_state_update_key(self.keyboard.state, keycode + 8, if (pressed != 0) xkb.XKB_KEY_DOWN else xkb.XKB_KEY_UP);
                }
            }
        },
        xcb.XCB_KEY_PRESS, xcb.XCB_KEY_RELEASE => {
            const event: *xcb.xcb_key_press_event_t = @ptrCast(generic_event);
            target_id = event.event;

            const state: PlatformWindow.Event.Key.State = switch (event_type) {
                xcb.XCB_KEY_PRESS => .pressed,
                xcb.XCB_KEY_RELEASE => .released,
                else => unreachable,
            };
            const keycode = event.detail;

            // _ = xkb.xkb_state_update_key(self.keyboard.state, keycode + 8, if (state == .pressed) xkb.XKB_KEY_DOWN else xkb.XKB_KEY_UP);
            const xkb_sym = xkb.xkb_state_key_get_one_sym(self.keyboard.state, keycode + 8);

            if (std.enums.fromInt(PlatformWindow.Event.Key.Sym, xkb_sym)) |sym| out_event = .{ .key = .{
                .state = state,
                .code = keycode,
                .sym = sym,
            } };
        },

        xcb.XCB_MOTION_NOTIFY => {
            const event: *xcb.xcb_motion_notify_event_t = @ptrCast(generic_event);
            target_id = event.event;
            const motion: PlatformWindow.Event.MouseMotion = .{ .x = @floatFromInt(event.event_x), .y = @floatFromInt(event.event_y) };

            out_event = .{ .mouse_motion = motion };
        },
        xcb.XCB_BUTTON_PRESS, xcb.XCB_BUTTON_RELEASE => {
            const event: *xcb.xcb_button_press_event_t = @ptrCast(generic_event);
            target_id = event.event;
            const state: PlatformWindow.Event.MouseButton.State = switch (event_type) {
                xcb.XCB_BUTTON_PRESS => .pressed,
                xcb.XCB_BUTTON_RELEASE => .released,
                else => unreachable,
            };

            out_event = switch (event.detail) {
                6 => .{ .mouse_scroll = .{ .horizontal = -1.0 } },
                7 => .{ .mouse_scroll = .{ .horizontal = 1.0 } },
                4 => .{ .mouse_scroll = .{ .vertical = 1.0 } },
                5 => .{ .mouse_scroll = .{ .vertical = -1.0 } },
                else => if (PlatformWindow.Event.MouseButton.Button.fromX(event.detail)) |button| .{ .mouse_button = .{
                    .state = state,
                    .button = button,
                } } else null,
            };
        },
        else => {},
    }
    if (generic_event.response_type == xcb.XCB_GE_GENERIC) {
        const extension_event: *xcb.xcb_ge_generic_event_t = @ptrCast(generic_event);

        if (self.extensions.xinput_opcode) |opcode| if (extension_event.extension == opcode) switch (extension_event.event_type) {
            xcb.XCB_INPUT_MOTION => {
                std.debug.print("xinput motion\n", .{});
            },
            xcb.XCB_INPUT_BUTTON_PRESS => {},
            xcb.XCB_INPUT_BUTTON_RELEASE => {},
            xcb.XCB_INPUT_TOUCH_BEGIN => {
                const event: *xcb.xcb_input_touch_begin_event_t = @ptrCast(generic_event);
                target_id = event.event;
            },
            xcb.XCB_INPUT_TOUCH_END => {},
            xcb.XCB_INPUT_TOUCH_UPDATE => {},
            else => {},
        };
    }

    if (out_event) |event| if (window.id == target_id) return out_event else {
        const target, _ = self.windowFromId(target_id).?;
        if (window.id == target.id) return event else {
            try target.event_queue.append(self.gpa, event);
        }
    };
    return windowPoll(context, platform_window);
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            _ = xcb.xcb_change_property(self.connection, xcb.XCB_PROP_MODE_REPLACE, window.id, xcb.XCB_ATOM_WM_NAME, xcb.XCB_ATOM_STRING, 8, @intCast(title.len), title.ptr);
            _ = xcb.xcb_change_property(self.connection, xcb.XCB_PROP_MODE_REPLACE, window.id, self.atom_table.net_wm.name, self.atom_table.utf8_string, 8, @intCast(title.len), title.ptr);
        },
        .size => |size| {
            var values = [_]u32{ size.width, size.height };

            _ = xcb.xcb_configure_window(
                self.connection,
                window.id,
                xcb.XCB_CONFIG_WINDOW_WIDTH | xcb.XCB_CONFIG_WINDOW_HEIGHT,
                &values,
            );
        },
        .position => |position| {
            var values = [_]u32{ @intCast(position.x), @intCast(position.y) };

            _ = xcb.xcb_configure_window(
                self.connection,
                window.id,
                xcb.XCB_CONFIG_WINDOW_X | xcb.XCB_CONFIG_WINDOW_Y,
                &values,
            );
        },
        .resize_policy => |resize_policy| {
            var hints: xcb.xcb_size_hints_t = .{};

            switch (resize_policy) {
                .resizable => |resizable| if (!resizable) {
                    const size = window.interface.size;
                    xcb.xcb_icccm_size_hints_set_max_size(&hints, @intCast(size.width), @intCast(size.height));
                    xcb.xcb_icccm_size_hints_set_min_size(&hints, @intCast(size.width), @intCast(size.height));
                },
                .specified => |specified| {
                    if (specified.max_size) |size| xcb.xcb_icccm_size_hints_set_max_size(&hints, @intCast(size.width), @intCast(size.height));
                    if (specified.min_size) |size| xcb.xcb_icccm_size_hints_set_min_size(&hints, @intCast(size.width), @intCast(size.height));
                },
            }

            _ = xcb.xcb_icccm_set_wm_normal_hints(self.connection, window.id, &hints);
        },
        .fullscreen => |fullscreen| {
            var event: xcb.xcb_client_message_event_t = .{
                .response_type = xcb.XCB_CLIENT_MESSAGE,
                .format = 32,
                .window = window.id,
                .type = self.atom_table.net_wm.state,
                .data = .{ .data32 = .{
                    @intFromBool(fullscreen),
                    self.atom_table.net_wm.state_fullscreen,
                    0,
                    0,
                    0,
                } },
            };

            _ = xcb.xcb_send_event(self.connection, 0, self.screen.root, xcb.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | xcb.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY, @ptrCast(&event));
        },
        .maximized => |maximized| {
            var event: xcb.xcb_client_message_event_t = .{
                .response_type = xcb.XCB_CLIENT_MESSAGE,
                .format = 32,
                .window = window.id,
                .type = self.atom_table.net_wm.state,
                .data = .{ .data32 = .{
                    @intFromBool(maximized),
                    self.atom_table.net_wm.state_maximized_horz,
                    self.atom_table.net_wm.state_maximized_vert,
                    0,
                    0,
                } },
            };

            _ = xcb.xcb_send_event(self.connection, 0, self.screen.root, xcb.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | xcb.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY, @ptrCast(&event));
        },
        .minimized => |minimized| {
            _ = if (minimized)
                xcb.xcb_unmap_window(self.connection, window.id)
            else
                xcb.xcb_map_window(self.connection, window.id);
        },
        .always_on_top => |always_on_top| {
            var event: xcb.xcb_client_message_event_t = .{
                .response_type = xcb.XCB_CLIENT_MESSAGE,
                .format = 32,
                .window = window.id,
                .type = self.atom_table.net_wm.state,
                .data = .{ .data32 = .{
                    @intFromBool(always_on_top),
                    self.atom_table.net_wm.state_above,
                    0,
                    0,
                    0,
                } },
            };

            _ = xcb.xcb_send_event(self.connection, 0, self.screen.root, xcb.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | xcb.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY, @ptrCast(&event));
        },
        .floating => {},
        .decorated => |decorated| {
            const MotifHints = extern struct {
                flags: u32,
                functions: u32,
                decorations: u32,
                input_mode: i32,
                status: u32,
            };
            const MWM_HINTS_DECORATIONS = 1 << 1;

            var hints = MotifHints{
                .flags = MWM_HINTS_DECORATIONS,
                .functions = 0,
                .decorations = @intFromBool(decorated),
                .input_mode = 0,
                .status = 0,
            };

            _ = xcb.xcb_change_property(
                self.connection,
                xcb.XCB_PROP_MODE_REPLACE,
                window.id,
                self.atom_table.motif_wm_hints,
                self.atom_table.motif_wm_hints,
                32,
                @sizeOf(MotifHints) / 4,
                &hints,
            );
        },
        .focused => |focused| if (focused) {
            _ = xcb.xcb_set_input_focus(
                self.connection,
                xcb.XCB_INPUT_FOCUS_POINTER_ROOT, // or XCB_INPUT_FOCUS_PARENT
                window.id,
                xcb.XCB_CURRENT_TIME,
            );

            var event: xcb.xcb_client_message_event_t = .{
                .response_type = xcb.XCB_CLIENT_MESSAGE,
                .format = 32,
                .window = window.id,
                .type = self.atom_table.net_wm.state,
                .data = .{ .data32 = .{
                    @intFromBool(focused),
                    self.atom_table.net_wm.active_window,
                    0,
                    0,
                    0,
                } },
            };

            _ = xcb.xcb_send_event(self.connection, 0, self.screen.root, xcb.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | xcb.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY, @ptrCast(&event));
        } else {
            _ = xcb.xcb_set_input_focus(
                self.connection,
                xcb.XCB_INPUT_FOCUS_POINTER_ROOT,
                self.screen.root,
                xcb.XCB_CURRENT_TIME,
            );

            var event: xcb.xcb_client_message_event_t = .{
                .response_type = xcb.XCB_CLIENT_MESSAGE,
                .format = 32,
                .window = 0, // no specific window,
                .type = self.atom_table.net_wm.active_window,
                .data = .{ .data32 = .{
                    1, xcb.XCB_CURRENT_TIME, 0, 0, 0,
                } },
            };

            _ = xcb.xcb_send_event(self.connection, 0, self.screen.root, xcb.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT | xcb.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY, @ptrCast(&event));
        },
        .cursor => {},
    }
    _ = xcb.xcb_flush(self.connection);
}
fn windowNative(context: *anyopaque, platform_window: *PlatformWindow) PlatformWindow.Native {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    return .{ .x11 = .{
        .display = self.connection,
        .window = @intCast(window.id),
        .screen = @intCast(self.screen.root),
    } };
}
fn windowFramebuffer(context: *anyopaque, platform_window: *PlatformWindow) anyerror!PlatformWindow.Framebuffer {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    // const cookie = xcb.xcb_get_image(self.connection, xcb.XCB_IMAGE_FORMAT_Z_PIXMAP, // format
    //     window.surface.framebuffer.pixmap, // your framebuffer pixmap
    //     0, 0, // x, y
    //     @intCast(window.interface.size.width), @intCast(window.interface.size.height), // size
    //     0xFFFFFFFF // plane mask (all planes)
    // );

    // const reply = xcb.xcb_get_image_reply(self.connection, cookie, null);
    // if (reply == null) return error.ImageReadFailed;

    // const pixels: [*]u8 = @ptrCast(reply + 1);

    // return .{ .pixels = pixels };

    _ = self;
    _ = window;
    return undefined;
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = xcb.xcb_glx_make_current(self.connection, window.id, window.surface.glx.context, 0);
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = xcb.xcb_glx_swap_buffers(self.connection, 0, window.id);
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *PlatformWindow, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    _ = interval;
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *PlatformWindow, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    const xcb_lib_names: []const [*:0]const u8 = &.{
        "libxcb.so.1",
        "libxcb.so.0",
        "libxcb.so",
    };

    var xcb_lib: std.DynLib = for (xcb_lib_names) |location| {
        break std.DynLib.openZ(location) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
    } else return error.LibXcbNotFound;
    defer xcb_lib.close();

    const xcb_connect = xcb_lib.lookup(*const fn (?[*:0]const u8, ?*c_int) callconv(.c) ?*xcb.xcb_connection_t, "xcb_connect") orelse return error.LookupXcbConnect;
    const xcb_disconnect = xcb_lib.lookup(*const fn (*xcb.xcb_connection_t) callconv(.c) void, "xcb_connect") orelse return error.LookupXcbDisconnect;

    const tmp_connection = xcb_connect(null, null) orelse return error.Connect;
    defer xcb_disconnect(tmp_connection);

    const vkCreateXcbSurfaceKHR: vulkan.SurfaceCreateProc = @ptrCast(loader(instance, "vkCreateXcbSurfaceKHR") orelse return error.LoadVkCreateXlibSurfaceKHR);

    const create_info: vulkan.SurfaceCreateInfo = .{ .xcb = .{
        .connection = tmp_connection,
        .window = window.id,
    } };

    var surface: ?*anyopaque = null;
    if (vkCreateXcbSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateXlibSurfaceKHR;
    return surface orelse error.InvalidSurface;
}

pub const Framebuffer = struct {
    shm: struct {
        seg: xcb.xcb_shm_seg_t,
        id: u32,
    },
    picture: xcb.xcb_render_picture_t,
    format_id: xcb.xcb_render_pictformat_t,
    pixels: [*]align(std.heap.page_size_min) u8,
    pub fn init(connection: *xcb.xcb_connection_t) !Framebuffer {
        _ = connection;
        // // Query XRender formats
        // const formats_cookie = xcb.xcb_render.xcb_render_query_pict_formats(connection);
        // const formats = xcb.xcb_render.xcb_render_query_pict_formats_reply(connection, formats_cookie, null) orelse return error.RenderQueryFailed;

        // // Find a 32-bit format
        // var format_info_it = xcb_render.xcb_render_query_pict_formats_formats_iterator(formats);
        // var format_id: xcb.xcb_render_pictformat_t = 0;
        // while (format_info_it.rem > 0) : (xcb_render.xcb_render_pictforminfo_next(&format_info_it)) {
        //     const format_info = format_info_it.data.?;
        //     if (format_info.depth != 32) continue;
        //     format_id = format_info.id;
        //     break;
        // }
        // if (format_id == 0) return error.NoValidFormatId;

        // return Framebuffer{
        //     .shm = .{ .seg = 0, .id = 0 },
        //     .picture = 0,
        //     .format_id = format_id,
        //     .pixels = null,
        //     .width = 0,
        //     .height = 0,
        //     .shmid = 0,
        // };
        return undefined;
    }

    pub fn resize(self: *@This(), connection: *xcb.xcb_connection_t, window: xcb.xcb_window_t, size: PlatformWindow.Size) !void {
        _ = self;
        _ = connection;
        _ = window;
        _ = size;
        // if (self.picture != 0) xcb.xcb_render_free_picture(connection, self.picture);

        // if (self.shm.seg != 0) {
        //     _ = xcb.xcb_shm_detach(connection, self.shm.seg);
        // }

        // const channels = 4;
        // const bytes: u32 = size.width * size.height * channels;

        // // Create SHM segment
        // self.shmid = std.posix.system.mmap(0, bytes, xcb.IPC_CREAT | 0o666) orelse return error.FailedToCreateSHM;
        // self.shm.seg = xcb.xcb_generate_id(connection);
        // xcb.xcb_shm_attach(connection, self.shm.seg, self.shmid, 0);

        // // Create XRender picture using the SHM pixmap
        // const shm_pixmap = xcb.xcb_generate_id(connection);
        // xcb.xcb_shm_pixmap_create(connection, shm_pixmap, window, width, height, 32, self.shm.seg);

        // self.picture = xcb.xcb_generate_id(connection);
        // xcb_render.xcb_render_create_picture(connection, self.picture, shm_pixmap, self.format_id, 0, null);
    }

    pub fn present(self: @This(), connection: *xcb.xcb_connection_t, size: PlatformWindow.Size) void {
        _ = xcb.xcb_render_composite(connection, xcb.XCB_RENDER_PICT_OP_OVER, // operation
            self.picture, // source picture (your framebuffer)
            0, // mask picture (XCB_RENDER_PICTURE_NONE)
            self.picture, // destination picture
            0, 0, // src_x, src_y
            0, 0, // mask_x, mask_y
            0, 0, // dst_x, dst_y
            @intCast(size.width), @intCast(size.height) // area to composite
        );
    }
};
