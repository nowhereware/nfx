package nfx

import SDL "vendor:sdl3"

VSync_Mode :: enum {
	Mailbox,
	FIFO,
	Immediate,
}

Swapchain_Internal :: union {
	Swapchain_Vk,
}

Swapchain :: struct {
	internal: Swapchain_Internal,
	device:   ^Device,
	vsync:    VSync_Mode,
	destroy:  proc(swapchain: ^Swapchain),
	resize:   proc(swapchain: ^Swapchain, size: [2]i32),
}

swapchain_init_sdl :: proc(
	device: ^Device,
	window: ^SDL.Window,
	vsync_mode: VSync_Mode,
	hdr: bool,
	swapchain: ^Swapchain,
) {
	swapchain.device = device
	switch device.ctx.backend {
	case .Vulkan:
		swapchain_vk_init_sdl(window, vsync_mode, hdr, swapchain)
	case .DX12:
	case .Metal:
	}
}
