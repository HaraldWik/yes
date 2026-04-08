const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");
const vk = @import("vulkan.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform: yes.Platform.Cross = try .init(allocator, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window: yes.Platform.Cross.Window = .empty(platform);
    const window = cross_window.interface(platform);
    try window.open(platform, .{
        .title = "vulkan triangle",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .resizable = false },
        .surface_type = .vulkan,
    });
    defer window.close(platform);

    // Instance
    const instance: vk.Instance = try .init(
        allocator,
        yes.vulkan.getRequiredInstanceExtensions([*:0]const u8, platform, window),
        &.{"VK_LAYER_KHRONOS_validation"},
    );
    defer instance.deinit();

    // VK_EXT_debug_utils
    // Debug messenger
    const debug_messenger = vk.setupDebugMessenger(instance) catch null;
    defer if (debug_messenger) |messenger| if (instance.getProcAddr(vk.c.PFN_vkDestroyDebugUtilsMessengerEXT, .vkDestroyDebugUtilsMessengerEXT) catch null) |vkDestroyDebugUtilsMessengerEXT|
        vkDestroyDebugUtilsMessengerEXT(instance.handle, messenger, null);

    // Surface
    const surface: vk.Surface = .{ .handle = @ptrCast(try yes.vulkan.createSurface(platform, window, instance.handle.?, null, @ptrCast(&vk.c.vkGetInstanceProcAddr))) };
    defer surface.deinit(instance);

    // Physical device
    const physical_device: vk.PhysicalDevice = try .pick(instance, allocator);
    const queue_family_index = try physical_device.getGraphicsQueueFamily(allocator, surface);
    const device: vk.Device = try .init(physical_device, &.{"VK_KHR_swapchain"}, queue_family_index);
    defer device.deinit();
    const graphics_queue = device.getQueue(queue_family_index);

    const surface_info = try surface.getInfo(allocator, physical_device);

    var swapchain: vk.Swapchain = std.mem.zeroes(vk.Swapchain);
    try swapchain.init(allocator, device, physical_device, surface, surface_info, .{});
    defer swapchain.deinit(allocator, device);

    const vertex_shader_module: vk.ShaderModule = try .initFromPath(allocator, io, device, "shaders/tri.vert.spv");
    const fragment_shader_module: vk.ShaderModule = try .initFromPath(allocator, io, device, "shaders/tri.frag.spv");

    const pipeline: vk.Pipeline = try .init(device, surface_info, vertex_shader_module, fragment_shader_module);
    defer pipeline.deinit(device);

    vertex_shader_module.deinit(device);
    fragment_shader_module.deinit(device);

    const command_pool: vk.CommandPool = try .init(device, queue_family_index);
    defer command_pool.deinit(device);

    var frame_data: vk.FrameData = try .init(allocator, device, swapchain);
    defer frame_data.deinit(allocator, device);

    main_loop: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main_loop,
            .resize => |size| {
                std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                try swapchain.resize(allocator, device, physical_device, surface, surface_info, size);
            },
            else => std.log.info("{any}", .{event}),
        };

        const command_buffer = try frame_data.aquire(device, swapchain, command_pool);

        var color_attachment: vk.c.VkRenderingAttachmentInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = swapchain.image_views[frame_data.image_index],
            .imageLayout = vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = vk.c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = .{
                .color = .{ .float32 = .{ 0.0, 0.15, 0.35, 1.0 } },
            },
        };

        var rendering_info: vk.c.VkRenderingInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.extent,
            },
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment,
        };

        vk.c.vkCmdBeginRendering(command_buffer, &rendering_info);

        vk.c.vkCmdBindPipeline(command_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);

        var viewport: vk.c.VkViewport = .{
            .width = @floatFromInt(swapchain.extent.width),
            .height = @floatFromInt(swapchain.extent.height),
            .maxDepth = 1.0,
        };

        var scissor: vk.c.VkRect2D = .{
            .extent = swapchain.extent,
            .offset = .{ .x = 0, .y = 0 },
        };
        vk.c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);
        vk.c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        vk.c.vkCmdDraw(command_buffer, 3, 1, 0, 0);
        vk.c.vkCmdEndRendering(command_buffer);

        try frame_data.present(swapchain, command_pool, graphics_queue);
    }

    try device.waitIdle();
}
