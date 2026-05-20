package nfx

import "core:fmt"
import "ext/vkb"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"

Swapchain_Vk :: struct {
	surface:     vk.SurfaceKHR,
	swapchain:   ^vkb.Swapchain,
	images:      []vk.Image,
	image_views: []vk.ImageView,
}

swapchain_vk_init_sdl :: proc(
	window: ^SDL.Window,
	vsync_mode: VSync_Mode,
	hdr: bool,
	swapchain: ^Swapchain,
) {
	cvk := &swapchain.device.ctx.internal.(Context_Vk)
	devvk := &swapchain.device.internal.(Device_Vk)
	svk: Swapchain_Vk

	if !SDL.Vulkan_CreateSurface(window, cvk.instance.instance, nil, &svk.surface) {
		fmt.eprintln("Failed to create Surface! SDL Error:", SDL.GetError())
	}

	// Ensure that present queues have been setup.
	if devvk.present_queue == nil {
		devvk.device.surface = svk.surface

		err: vkb.Error
		devvk.present_queue, err = vkb.device_get_queue(devvk.device, .Present)

		if err != nil {
			fmt.eprintln("Failed to create Present queue! Error:", err)
		}

		devvk.present_index, err = vkb.device_get_queue_index(devvk.device, .Present)

		if err != nil {
			fmt.eprintln("Failed to get Present queue index! Error:", err)
		}
	}

	swapchain_builder := vkb.create_swapchain_builder(devvk.device, svk.surface)
	defer vkb.destroy_swapchain_builder(swapchain_builder)

	present_mode: vk.PresentModeKHR
	switch vsync_mode {
	case .Mailbox:
		present_mode = .MAILBOX
	case .FIFO:
		present_mode = .FIFO
	case .Immediate:
		present_mode = .IMMEDIATE
	}

	vkb.swapchain_builder_set_desired_present_mode(swapchain_builder, present_mode)
	vkb.swapchain_builder_add_fallback_present_mode(swapchain_builder, .FIFO)

	// Query HDR support.
	format := vk.SurfaceFormatKHR {
		format     = .R8G8B8A8_SRGB,
		colorSpace = .SRGB_NONLINEAR,
	}

	if hdr {
		// Ensure our window has HDR.
		win_props := SDL.GetWindowProperties(window)

		hdr_enabled := SDL.GetBooleanProperty(
			win_props,
			SDL.PROP_WINDOW_HDR_ENABLED_BOOLEAN,
			false,
		)

		if hdr_enabled {
			format.format = .A2B10G10R10_UNORM_PACK32
			format.colorSpace = .HDR10_ST2084_EXT
		}
	}

	vkb.swapchain_builder_set_desired_format(swapchain_builder, format)
	vkb.swapchain_builder_set_desired_min_image_count(
		swapchain_builder,
		swapchain.device.frame_count,
	)

	err: vkb.Error
	svk.swapchain, err = vkb.swapchain_builder_build(swapchain_builder)

	if err != nil {
		fmt.eprintln("Failed to create Swapchain! Error:", err)
	}

	svk.images, err = vkb.swapchain_get_images(svk.swapchain)

	if err != nil {
		fmt.eprintln("Failed to get swapchain images! Error:", err)
	}

	svk.image_views, err = vkb.swapchain_get_image_views(svk.swapchain)

	if err != nil {
		fmt.eprintln("Failed to get swapchain image views! Error:", err)
	}

	swapchain.internal = svk
	swapchain.destroy = swapchain_vk_destroy
}

swapchain_vk_destroy :: proc(swapchain: ^Swapchain) {
	svk := &swapchain.internal.(Swapchain_Vk)
	cvk := &swapchain.device.ctx.internal.(Context_Vk)

	vkb.swapchain_destroy_image_views(svk.swapchain, svk.image_views)
	delete(svk.image_views)
	delete(svk.images)
	vkb.destroy_swapchain(svk.swapchain)
	vk.DestroySurfaceKHR(cvk.instance.instance, svk.surface, nil)
}
