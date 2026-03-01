const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

const vk = @import("vulkan");
pub const c = vk;

pub const max_frames_in_flight = 3;

pub fn check(result: vk.VkResult) !void {
    return switch (result) {
        vk.VK_SUCCESS => {},
        vk.VK_NOT_READY => error.NotReady,
        vk.VK_TIMEOUT => error.Timeout,
        vk.VK_EVENT_SET => error.EventSet,
        vk.VK_EVENT_RESET => error.EventReset,
        vk.VK_INCOMPLETE => error.Incomplete,
        vk.VK_ERROR_OUT_OF_HOST_MEMORY => error.OutOfHostMemory,
        vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => error.OutOfDeviceMemory,
        vk.VK_ERROR_INITIALIZATION_FAILED => error.InitializationFailed,
        vk.VK_ERROR_DEVICE_LOST => error.DeviceLost,
        vk.VK_ERROR_MEMORY_MAP_FAILED => error.MemoryMapFailed,
        vk.VK_ERROR_LAYER_NOT_PRESENT => error.LayerNotPresent,
        vk.VK_ERROR_EXTENSION_NOT_PRESENT => error.ExtensionNotPresent,
        vk.VK_ERROR_FEATURE_NOT_PRESENT => error.FeatureNotPresent,
        vk.VK_ERROR_INCOMPATIBLE_DRIVER => error.IncompatibleDriver,
        vk.VK_ERROR_TOO_MANY_OBJECTS => error.TooManyObjects,
        vk.VK_ERROR_FORMAT_NOT_SUPPORTED => error.FormatNotSupported,
        vk.VK_ERROR_FRAGMENTED_POOL => error.FragmentedPool,
        vk.VK_ERROR_UNKNOWN => error.Unknown,
        vk.VK_ERROR_VALIDATION_FAILED => error.ValidationFailed,
        vk.VK_ERROR_OUT_OF_POOL_MEMORY => error.OutOfPoolMemory,
        vk.VK_ERROR_INVALID_EXTERNAL_HANDLE => error.InvalidExternalHandle,
        vk.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.InvalidOpaqueCaptureAddress,
        vk.VK_ERROR_FRAGMENTATION => error.Fragmentation,
        vk.VK_PIPELINE_COMPILE_REQUIRED => error.PipelineCompileRequired,
        vk.VK_ERROR_NOT_PERMITTED => error.NotPermitted,
        vk.VK_ERROR_SURFACE_LOST_KHR => error.SurfaceLostKhr,
        vk.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.NativeWindowInUseKhr,
        vk.VK_SUBOPTIMAL_KHR => error.SuboptimalKhr,
        vk.VK_ERROR_OUT_OF_DATE_KHR => error.OutOfDateKhr,
        vk.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.IncompatibleDisplayKhr,
        vk.VK_ERROR_INVALID_SHADER_NV => error.InvalidShaderNv,
        vk.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.ImageUsageNotSupportedKhr,
        vk.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.VideoPictureLayoutNotSupportedKhr,
        vk.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.VideoProfileOperationNotSupportedKhr,
        vk.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.VideoProfileFormatNotSupportedKhr,
        vk.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.VideoProfileCodecNotSupportedKhr,
        vk.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.VideoStdVersionNotSupportedKhr,
        vk.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.InvalidDrmFormatModifierPlaneLayoutExt,
        vk.VK_ERROR_PRESENT_TIMING_QUEUE_FULL_EXT => error.PresentTimingQueueFullExt,
        vk.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.FullScreenExclusiveModeLostExt,
        vk.VK_THREAD_IDLE_KHR => error.ThreadIdleKhr,
        vk.VK_THREAD_DONE_KHR => error.ThreadDoneKhr,
        vk.VK_OPERATION_DEFERRED_KHR => error.OperationDeferredKhr,
        vk.VK_OPERATION_NOT_DEFERRED_KHR => error.OperationNotDeferredKhr,
        vk.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => error.InvalidVideoStdParametersKhr,
        vk.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => error.CompressionExhaustedExt,
        vk.VK_INCOMPATIBLE_SHADER_BINARY_EXT => error.IncompatibleShaderBinaryExt,
        vk.VK_PIPELINE_BINARY_MISSING_KHR => error.PipelineBinaryMissingKhr,
        vk.VK_ERROR_NOT_ENOUGH_SPACE_KHR => error.NotEnoughSpaceKhr,
        else => error.Unknown,
    };
}
pub const Instance = struct {
    handle: vk.VkInstance,

    pub fn init(allocator: std.mem.Allocator, required_extensions: []const [*:0]const u8, layers: []const [*:0]const u8) !@This() {
        var version: u32 = undefined;
        try check(vk.vkEnumerateInstanceVersion(&version));
        if (vk.VK_API_VERSION_MAJOR(version) < 1 or vk.VK_API_VERSION_MINOR(version) < 3) return error.DynamicRenderingUnsupported;

        var count: u32 = undefined;
        try check(vk.vkEnumerateInstanceExtensionProperties(null, &count, null));

        const enum_extensions: []vk.VkExtensionProperties = try allocator.alloc(vk.VkExtensionProperties, count);
        defer allocator.free(enum_extensions);

        try check(vk.vkEnumerateInstanceExtensionProperties(null, &count, enum_extensions.ptr));

        var found: usize = 0;

        for (enum_extensions) |enum_extension| {
            const extension_name_len = std.mem.findScalar(u8, enum_extension.extensionName[0..], 0).?;
            for (required_extensions) |required_extension| {
                if (!std.mem.eql(u8, std.mem.span(required_extension), (enum_extension.extensionName[0..extension_name_len]))) continue;
                std.log.info("found ext: [{d}/{d}] {s}", .{ found + 1, required_extensions.len, required_extension });
                found += 1;
            }
        }
        if (found != required_extensions.len) return error.ExtensionsNotFound;

        var instance: vk.VkInstance = undefined;
        const instane_create_info: *const vk.VkInstanceCreateInfo = &.{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &.{
                .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pApplicationName = "Hello Triangle",
                .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
                .pEngineName = "No Engine",
                .engineVersion = vk.VK_MAKE_VERSION(1, 0, 0),
                .apiVersion = vk.VK_API_VERSION_1_3,
            },
            .enabledExtensionCount = @intCast(required_extensions.len),
            .ppEnabledExtensionNames = required_extensions.ptr,
            .enabledLayerCount = @intCast(layers.len),
            .ppEnabledLayerNames = layers.ptr,
        };
        try check(vk.vkCreateInstance(instane_create_info, null, @ptrCast(&instance)));
        return .{ .handle = instance };
    }

    pub fn deinit(self: @This()) void {
        vk.vkDestroyInstance(self.handle, null);
    }

    pub fn getProcAddr(self: @This(), comptime T: type, name: @EnumLiteral()) !T {
        return @ptrCast(vk.vkGetInstanceProcAddr(self.handle, @tagName(name)) orelse return error.Load);
    }
};
pub fn setupDebugMessenger(instance: Instance) !vk.VkDebugUtilsMessengerEXT {
    const debug_messenger_create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debugCallback,
        .pUserData = null,
    };

    var debug_messenger: vk.VkDebugUtilsMessengerEXT = undefined;

    const fn_ptr: ?*const fn (vk.VkInstance, *const vk.VkDebugUtilsMessengerCreateInfoEXT, ?*const vk.VkAllocationCallbacks, *vk.VkDebugUtilsMessengerEXT) callconv(.c) vk.VkResult = @ptrCast(vk.vkGetInstanceProcAddr(instance.handle, "vkCreateDebugUtilsMessengerEXT"));

    if (fn_ptr == null) return error.ExtensionNotPresent;

    try check(fn_ptr.?(instance.handle, &debug_messenger_create_info, null, &debug_messenger));

    return debug_messenger;
}
fn debugCallback(message_severity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT, message_type: vk.VkDebugUtilsMessageTypeFlagsEXT, callback_data: [*c]const vk.VkDebugUtilsMessengerCallbackDataEXT, user_data: ?*anyopaque) callconv(.c) u32 {
    _ = message_type;
    _ = user_data;
    const scope = std.log.scoped(.vulkan);

    switch (message_severity) {
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT, vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => scope.info("{s}", .{callback_data.*.pMessage}),
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => scope.warn("{s}", .{callback_data.*.pMessage}),
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => scope.err("{s}", .{callback_data.*.pMessage}),
        else => unreachable,
    }
    return vk.VK_FALSE;
}

pub const Surface = struct {
    handle: vk.VkSurfaceKHR,

    pub const Info = struct {
        capabilities: vk.VkSurfaceCapabilitiesKHR,
        format: vk.VkSurfaceFormatKHR,
    };

    // pub fn init(instance: Instance, platform: yes.Platform, window: *yes.Platform.Window) !@This() {
    //     var surface: vk.VkSurfaceKHR = undefined;
    //     switch (builtin.os.tag) {
    //         .windows => {
    //             const win32_platform: *yes.Platform.Win32 = @ptrCast(@alignCast(platform.ptr));

    //             const win32_window: *yes.Platform.Win32.Window = @alignCast(@fieldParentPtr("interface", window));

    //             var surface_create_info: vk.VkWin32SurfaceCreateInfoKHR = .{
    //                 .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
    //                 .hinstance = win32_platform.instance,
    //                 .hwnd = win32_window.hwnd,
    //             };
    //             try check(vk.vkCreateWin32SurfaceKHR(instance.handle, &surface_create_info, null, &surface));
    //         },
    //         else => switch (window.handle) {
    //             .wayland => {
    //                 var surface_create_info: vk.VkWaylandSurfaceCreateInfoKHR = .{
    //                     .sType = vk.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
    //                     .display = @ptrCast(window.handle.wayland.display),
    //                     .surface = @ptrCast(window.handle.wayland.surface),
    //                 };

    //                 try check(vk.vkCreateWaylandSurfaceKHR(instance.handle, &surface_create_info, null, &surface));
    //             },
    //             .x11 => {
    //                 var surface_create_info: vk.VkXlibSurfaceCreateInfoKHR = .{
    //                     .sType = vk.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
    //                     .dpy = @ptrCast(window.handle.x11.display),
    //                     .window = @intCast(window.handle.x11.window),
    //                 };

    //                 try check(vk.vkCreateXlibSurfaceKHR(instance.handle, &surface_create_info, null, &surface));
    //             },
    //         },
    //     }
    //     return .{ .handle = surface };
    // }

    pub fn deinit(self: @This(), instance: Instance) void {
        vk.vkDestroySurfaceKHR(instance.handle, self.handle, null);
    }

    pub fn getInfo(self: @This(), allocator: std.mem.Allocator, physical_device: PhysicalDevice) !Info {
        var capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
        try check(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.handle, self.handle, &capabilities));

        var format_count: u32 = undefined;
        try check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.handle, self.handle, &format_count, null));

        const formats: []vk.VkSurfaceFormatKHR = try allocator.alloc(vk.VkSurfaceFormatKHR, format_count);
        defer allocator.free(formats);
        try check(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.handle, self.handle, &format_count, formats.ptr));

        const format = for (formats) |format| {
            if (format.format == vk.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) break format;
        } else formats[0];

        return .{ .capabilities = capabilities, .format = format };
    }
};

pub const PhysicalDevice = struct {
    handle: vk.VkPhysicalDevice,

    // pub const QueueFamilyIndices = struct {
    //     graphics_family: u32,

    //     pub fn find(physical_device: PhysicalDevice) !@This() {}
    // };

    pub fn isSuitable(physical_device: @This()) bool {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        var features: vk.VkPhysicalDeviceFeatures = undefined;
        vk.vkGetPhysicalDeviceProperties(physical_device.handle, &properties);
        vk.vkGetPhysicalDeviceFeatures(physical_device.handle, &features);

        const is_suitable = properties.deviceType == vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and features.geometryShader == 1;
        if (is_suitable) std.log.info("found physical device: {s}", .{properties.deviceName});
        return is_suitable;
    }

    pub fn pick(instance: Instance, allocator: std.mem.Allocator) !@This() {
        var physical_device_count: u32 = undefined;
        try check(vk.vkEnumeratePhysicalDevices(instance.handle, &physical_device_count, null));
        const physical_devices: []vk.VkPhysicalDevice = try allocator.alloc(vk.VkPhysicalDevice, physical_device_count);
        defer allocator.free(physical_devices);
        try check(vk.vkEnumeratePhysicalDevices(instance.handle, &physical_device_count, physical_devices.ptr));

        for (physical_devices) |physical_device| {
            if (isSuitable(.{ .handle = physical_device })) return .{ .handle = physical_device };
        }
        return error.NoSuitablePhysicalDevice;
    }

    pub fn getGraphicsQueueFamily(self: @This(), allocator: std.mem.Allocator, surface: Surface) !u32 {
        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(self.handle, &queue_family_count, null);

        const queue_families: []vk.VkQueueFamilyProperties = try allocator.alloc(vk.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(self.handle, &queue_family_count, queue_families.ptr);

        var graphics_queue_family: u32 = std.math.maxInt(u32);
        for (queue_families, 0..) |queue_family, i| {
            var present_support: vk.VkBool32 = vk.VK_FALSE;
            try check(vk.vkGetPhysicalDeviceSurfaceSupportKHR(self.handle, @intCast(i), surface.handle, &present_support));

            if ((queue_family.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == 1) and present_support == 1) {
                graphics_queue_family = @intCast(i);
                break;
            }
        }

        if (graphics_queue_family == std.math.maxInt(u32)) return error.NoGraphicsQueueFamilyFound;
        return graphics_queue_family;
    }
};

pub const Device = struct {
    handle: vk.VkDevice,

    pub fn init(physical_device: PhysicalDevice, extensions: []const [*:0]const u8, graphics_queue_family: u32) !@This() {
        var queue_priority: f32 = 1.0;
        var queue_create_info: vk.VkDeviceQueueCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = graphics_queue_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        var vulkan13_features: vk.VkPhysicalDeviceVulkan13Features = .{
            .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            .synchronization2 = vk.VK_TRUE,
            .dynamicRendering = vk.VK_TRUE,
        };

        var features: vk.VkPhysicalDeviceFeatures2 = .{
            .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            .pNext = &vulkan13_features,
        };

        var create_info: vk.VkDeviceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_create_info,
            .enabledExtensionCount = @intCast(extensions.len),
            .ppEnabledExtensionNames = extensions.ptr,
            .pNext = &features,
        };

        var device: vk.VkDevice = undefined;
        try check(vk.vkCreateDevice(physical_device.handle, &create_info, null, &device));
        return .{ .handle = device };
    }

    pub fn deinit(self: @This()) void {
        vk.vkDestroyDevice(self.handle, null);
    }

    pub fn getQueue(self: @This(), queue_family_index: u32) vk.VkQueue {
        var queue: vk.VkQueue = undefined;
        vk.vkGetDeviceQueue(self.handle, queue_family_index, 0, &queue);
        return queue;
    }

    pub fn waitIdle(self: @This()) !void {
        try check(vk.vkDeviceWaitIdle(self.handle));
    }
};

pub const ShaderModule = struct {
    handle: vk.VkShaderModule,

    pub fn initFromSlice(device: Device, slice: []align(4) const u8) !@This() {
        var create_info: vk.VkShaderModuleCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = slice.len,
            .pCode = @ptrCast(slice.ptr),
        };

        var shader_module: vk.VkShaderModule = undefined;
        try check(vk.vkCreateShaderModule(device.handle, &create_info, null, &shader_module));

        return .{ .handle = shader_module };
    }

    pub fn initFromPath(allocator: std.mem.Allocator, io: std.Io, device: Device, sub_path: []const u8) !@This() {
        const source: []align(4) u8 = try std.Io.Dir.cwd().readFileAllocOptions(io, sub_path, allocator, .unlimited, .@"4", null);
        defer allocator.free(source);
        return .initFromSlice(device, source);
    }

    pub fn deinit(self: @This(), device: Device) void {
        vk.vkDestroyShaderModule(device.handle, self.handle, null);
    }
};

pub const Swapchain = struct {
    handle: vk.VkSwapchainKHR,
    extent: vk.VkExtent2D,
    images: []vk.VkImage,
    image_views: []vk.VkImageView,
    present_mode: ?vk.VkPresentModeKHR = null,

    pub fn init(self: *@This(), allocator: std.mem.Allocator, device: Device, physical_device: PhysicalDevice, surface: Surface, surface_info: Surface.Info, size: yes.Platform.Window.Size) !void {
        self.extent.width = @intCast(size.width);
        self.extent.height = @intCast(size.height);

        self.extent.width = @min(surface_info.capabilities.maxImageExtent.width, self.extent.width);
        self.extent.height = @min(surface_info.capabilities.maxImageExtent.height, self.extent.height);
        self.extent.width = @max(surface_info.capabilities.minImageExtent.width, self.extent.width);
        self.extent.height = @max(surface_info.capabilities.minImageExtent.height, self.extent.height);

        // one more for triple buffering
        var min_image_count = surface_info.capabilities.minImageCount + 1;
        if (surface_info.capabilities.maxImageCount > 0) {
            min_image_count = @min(min_image_count, surface_info.capabilities.maxImageCount);
        }

        // swapchain present mode
        if (self.present_mode == null) {
            var present_modes_count: u32 = undefined;
            try check(vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device.handle, surface.handle, &present_modes_count, null));
            const present_modes: []vk.VkPresentModeKHR = try allocator.alloc(vk.VkPresentModeKHR, present_modes_count);
            defer allocator.free(present_modes);
            try check(vk.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device.handle, surface.handle, &present_modes_count, present_modes.ptr));

            var found_present_mode: u32 = vk.VK_PRESENT_MODE_FIFO_KHR;

            for (present_modes) |mode| {
                if (mode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
                    found_present_mode = mode;
                    break;
                }

                if (mode == vk.VK_PRESENT_MODE_IMMEDIATE_KHR) {
                    found_present_mode = mode;
                } else if (mode == vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR and found_present_mode == vk.VK_PRESENT_MODE_FIFO_KHR) {
                    found_present_mode = mode;
                }
            }
            const present_mode_name = switch (found_present_mode) {
                vk.VK_PRESENT_MODE_MAILBOX_KHR => "mailbox",
                vk.VK_PRESENT_MODE_IMMEDIATE_KHR => "immediate",
                vk.VK_PRESENT_MODE_FIFO_RELAXED_KHR => "fifo_relaxed",
                vk.VK_PRESENT_MODE_FIFO_KHR => "fifo",
                else => "unknown",
            };
            std.log.info("found present mode: {s}", .{present_mode_name});
            self.present_mode = found_present_mode;
        }

        var create_info: vk.VkSwapchainCreateInfoKHR = .{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface.handle,
            .minImageCount = min_image_count,
            .imageFormat = surface_info.format.format,
            .imageColorSpace = surface_info.format.colorSpace,
            .imageExtent = self.extent,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .preTransform = surface_info.capabilities.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = self.present_mode.?,
            .clipped = vk.VK_TRUE,
        };

        try check(vk.vkCreateSwapchainKHR(device.handle, &create_info, null, &self.handle));

        var image_count: u32 = undefined;
        try check(vk.vkGetSwapchainImagesKHR(device.handle, self.handle, &image_count, null));
        self.images = try allocator.alloc(vk.VkImage, image_count);
        // defer allocator.free(self.images);
        try check(vk.vkGetSwapchainImagesKHR(device.handle, self.handle, &image_count, self.images.ptr));

        self.image_views = try allocator.alloc(vk.VkImageView, image_count);

        for (self.images, self.image_views) |image, *image_view| {
            var image_view_create_info: vk.VkImageViewCreateInfo = .{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
                .format = surface_info.format.format,
                .components = .{
                    .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            try check(vk.vkCreateImageView(device.handle, &image_view_create_info, null, image_view));
        }
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator, device: Device) void {
        for (self.image_views) |image_view| vk.vkDestroyImageView(device.handle, image_view, null);

        allocator.free(self.image_views);
        allocator.free(self.images);

        vk.vkDestroySwapchainKHR(device.handle, self.handle, null);
    }

    pub fn resize(self: *@This(), allocator: std.mem.Allocator, device: Device, physical_device: PhysicalDevice, surface: Surface, surface_info: Surface.Info, size: yes.Platform.Window.Size) !void {
        try device.waitIdle();
        self.deinit(allocator, device);
        try self.init(allocator, device, physical_device, surface, surface_info, size);
    }
};

pub const Pipeline = struct {
    handle: vk.VkPipeline,
    layout: vk.VkPipelineLayout,

    pub fn init(device: Device, surface_info: Surface.Info, vertex_shader_module: ShaderModule, fragment_shader_module: ShaderModule) !@This() {
        var shader_stages: []const vk.VkPipelineShaderStageCreateInfo = &.{
            .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = vk.VK_SHADER_STAGE_VERTEX_BIT,
                .module = vertex_shader_module.handle,
                .pName = "main",
            },
            .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = fragment_shader_module.handle,
                .pName = "main",
            },
        };

        var vertex_input_state: vk.VkPipelineVertexInputStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 0,
            .vertexAttributeDescriptionCount = 0,
        };

        var input_assembly_state: vk.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = vk.VK_FALSE,
        };

        var viewport_state: vk.VkPipelineViewportStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        var rasterization_state: vk.VkPipelineRasterizationStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = vk.VK_FALSE,
            .rasterizerDiscardEnable = vk.VK_FALSE,
            .polygonMode = vk.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = vk.VK_CULL_MODE_BACK_BIT,
            .frontFace = vk.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasClamp = vk.VK_FALSE,
        };

        var multisample_state: vk.VkPipelineMultisampleStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = vk.VK_FALSE,
            .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        };

        var color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
            .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT |
                vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = vk.VK_FALSE,
        };

        var color_blend_state: vk.VkPipelineColorBlendStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = vk.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment,
        };

        const dynamic_states: []const vk.VkDynamicState = &.{
            vk.VK_DYNAMIC_STATE_VIEWPORT,
            vk.VK_DYNAMIC_STATE_SCISSOR,
        };

        var dynamic_state: vk.VkPipelineDynamicStateCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = @intCast(dynamic_states.len),
            .pDynamicStates = dynamic_states.ptr,
        };

        var pipeline_layout_create_info: vk.VkPipelineLayoutCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 0,
            .pushConstantRangeCount = 0,
        };

        var pipeline_layout: vk.VkPipelineLayout = undefined;
        try check(vk.vkCreatePipelineLayout(device.handle, &pipeline_layout_create_info, null, &pipeline_layout));

        var pipeline_rendering_create_info: vk.VkPipelineRenderingCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .colorAttachmentCount = 1,
            .pColorAttachmentFormats = &surface_info.format.format,
        };

        var graphics_pipeline_create_info: vk.VkGraphicsPipelineCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &pipeline_rendering_create_info,
            .stageCount = @intCast(shader_stages.len),
            .pStages = shader_stages.ptr,
            .pVertexInputState = &vertex_input_state,
            .pInputAssemblyState = &input_assembly_state,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterization_state,
            .pMultisampleState = &multisample_state,
            .pColorBlendState = &color_blend_state,
            .pDynamicState = &dynamic_state,
            .layout = pipeline_layout,
            .renderPass = null,
            .subpass = 0,
        };

        var graphics_pipeline: vk.VkPipeline = undefined;
        try check(vk.vkCreateGraphicsPipelines(device.handle, null, 1, &graphics_pipeline_create_info, null, &graphics_pipeline));
        return .{ .handle = graphics_pipeline, .layout = pipeline_layout };
    }

    pub fn deinit(self: @This(), device: Device) void {
        vk.vkDestroyPipelineLayout(device.handle, self.layout, null);
        vk.vkDestroyPipeline(device.handle, self.handle, null);
    }
};

pub const CommandPool = struct {
    handle: vk.VkCommandPool,
    buffers: [max_frames_in_flight]vk.VkCommandBuffer,

    pub fn init(device: Device, queue_family_index: u32) !@This() {
        var command_pool_create_info: vk.VkCommandPoolCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family_index,
        };

        var command_pool: vk.VkCommandPool = undefined;
        try check(vk.vkCreateCommandPool(device.handle, &command_pool_create_info, null, &command_pool));

        var command_buffer_allocate_info: vk.VkCommandBufferAllocateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = command_pool, .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = max_frames_in_flight };

        var command_buffers: [max_frames_in_flight]vk.VkCommandBuffer = undefined;
        try check(vk.vkAllocateCommandBuffers(device.handle, &command_buffer_allocate_info, &command_buffers));

        return .{ .handle = command_pool, .buffers = command_buffers };
    }

    pub fn deinit(self: @This(), device: Device) void {
        vk.vkDestroyCommandPool(device.handle, self.handle, null);
    }
};

pub const FrameData = struct {
    current_frame: usize = 0,
    image_index: u32 = 0,
    sync: Sync,

    pub const Sync = struct {
        image_available_semaphores: [max_frames_in_flight]vk.VkSemaphore,
        flight_fences: [max_frames_in_flight]vk.VkFence,
        render_finished_semaphore: []vk.VkSemaphore,

        pub fn init(allocator: std.mem.Allocator, device: Device, swapchain: Swapchain) !@This() {
            var semaphore_create_info: vk.VkSemaphoreCreateInfo = .{
                .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            };

            var fence_create_info: vk.VkFenceCreateInfo = .{
                .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
            };

            var image_available_semaphores: [max_frames_in_flight]vk.VkSemaphore = undefined;
            var flight_fences: [max_frames_in_flight]vk.VkFence = undefined;

            for (image_available_semaphores[0..], flight_fences[0..]) |*semaphore, *flight_fence| {
                try check(vk.vkCreateSemaphore(device.handle, &semaphore_create_info, null, semaphore));
                try check(vk.vkCreateFence(device.handle, &fence_create_info, null, flight_fence));
            }

            const render_finished_semaphore: []vk.VkSemaphore = try allocator.alloc(vk.VkSemaphore, swapchain.images.len);
            for (render_finished_semaphore) |*semaphore| try check(vk.vkCreateSemaphore(device.handle, &semaphore_create_info, null, semaphore));

            return .{
                .image_available_semaphores = image_available_semaphores,
                .flight_fences = flight_fences,
                .render_finished_semaphore = render_finished_semaphore,
            };
        }

        pub fn deinit(self: @This(), allocator: std.mem.Allocator, device: Device) void {
            for (self.image_available_semaphores) |semaphore| vk.vkDestroySemaphore(device.handle, semaphore, null);
            for (self.flight_fences) |fence| vk.vkDestroyFence(device.handle, fence, null);
            for (self.render_finished_semaphore) |semaphore| vk.vkDestroySemaphore(device.handle, semaphore, null);
            allocator.free(self.render_finished_semaphore);
        }
    };

    pub fn init(allocator: std.mem.Allocator, device: Device, swapchain: Swapchain) !@This() {
        const sync: Sync = try .init(allocator, device, swapchain);
        return .{ .sync = sync };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator, device: Device) void {
        self.sync.deinit(allocator, device);
    }

    pub fn aquire(self: *@This(), device: Device, swapchain: Swapchain, command_pool: CommandPool) !vk.VkCommandBuffer {
        try check(vk.vkWaitForFences(device.handle, 1, &self.sync.flight_fences[self.current_frame], vk.VK_TRUE, std.math.maxInt(u64)));
        try check(vk.vkResetFences(device.handle, 1, &self.sync.flight_fences[self.current_frame]));

        try check(vk.vkAcquireNextImageKHR(device.handle, swapchain.handle, std.math.maxInt(u64), self.sync.image_available_semaphores[self.current_frame], null, &self.image_index));

        const command_buffer: vk.VkCommandBuffer = command_pool.buffers[self.current_frame];
        try check(vk.vkResetCommandBuffer(command_buffer, 0));

        var command_buffer_begin_info: vk.VkCommandBufferBeginInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };
        try check(vk.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info));
        // undefined -> color attachment
        var barrier_to_render: vk.VkImageMemoryBarrier2 = .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            .srcAccessMask = 0,

            .dstStageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,

            .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,

            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,

            .image = swapchain.images[self.image_index],

            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        var dependency_to_render: vk.VkDependencyInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &barrier_to_render,
        };
        vk.vkCmdPipelineBarrier2(command_buffer, &dependency_to_render);

        return command_buffer;
    }

    pub fn present(self: *@This(), swapchain: Swapchain, command_pool: CommandPool, graphics_queue: vk.VkQueue) !void {
        const command_buffer: vk.VkCommandBuffer = command_pool.buffers[self.current_frame];

        var barrier_to_present: vk.VkImageMemoryBarrier2 = .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .dstStageMask = vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
            .dstAccessMask = 0,
            .oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,

            .image = swapchain.images[self.image_index],
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        var dependency_to_present: vk.VkDependencyInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &barrier_to_present,
        };

        vk.vkCmdPipelineBarrier2(command_buffer, &dependency_to_present);

        try check(vk.vkEndCommandBuffer(command_buffer));

        var wait_semaphore_info: vk.VkSemaphoreSubmitInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = self.sync.image_available_semaphores[self.current_frame], .stageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT };

        var signal_semaphore_info: vk.VkSemaphoreSubmitInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = self.sync.render_finished_semaphore[self.image_index], .stageMask = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT };

        var command_buffer_info: vk.VkCommandBufferSubmitInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = command_buffer,
        };

        var submit_info: vk.VkSubmitInfo2 = .{ .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2, .waitSemaphoreInfoCount = 1, .pWaitSemaphoreInfos = &wait_semaphore_info, .commandBufferInfoCount = 1, .pCommandBufferInfos = &command_buffer_info, .signalSemaphoreInfoCount = 1, .pSignalSemaphoreInfos = &signal_semaphore_info };

        try check(vk.vkQueueSubmit2(graphics_queue, 1, &submit_info, self.sync.flight_fences[self.current_frame]));

        var present_info: vk.VkPresentInfoKHR = .{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.sync.render_finished_semaphore[self.image_index],
            .swapchainCount = 1,
            .pSwapchains = &swapchain.handle,
            .pImageIndices = &self.image_index,
        };

        try check(vk.vkQueuePresentKHR(graphics_queue, &present_info));

        self.current_frame = (self.current_frame + 1) % max_frames_in_flight;
    }
};
