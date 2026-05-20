package nfx

import "core:fmt"
import "ext/vkb"
import "ext/vma"
import vk "vendor:vulkan"

Device_Vk :: struct {
	device:         ^vkb.Device,
	allocator:      vma.Allocator,
	vk_functions:   vma.Vulkan_Functions,
	graphics_queue: vk.Queue,
	graphics_index: u32,
	present_queue:  vk.Queue,
	present_index:  u32,
}

device_vk_init :: proc(ctx: ^Context, ref: ^Device_Reference, device: ^Device) {
	ctxvk := &ctx.internal.(Context_Vk)
	refvk := &ref.internal.(Device_Reference_Vk)
	device.internal = Device_Vk{}
	devvk := &device.internal.(Device_Vk)

	// Build device from reference.
	device_builder := vkb.create_device_builder(refvk.phys_device)
	defer vkb.destroy_device_builder(device_builder)

	err: vkb.Error
	devvk.device, err = vkb.device_builder_build(device_builder)

	if err != nil {
		fmt.eprintln("Failed to create Device from reference! Error:", err)
	}

	devvk.graphics_queue, err = vkb.device_get_queue(devvk.device, .Graphics)

	if err != nil {
		fmt.eprintln("Failed to get Graphics queue! Error:", err)
	}

	devvk.graphics_index, err = vkb.device_get_queue_index(devvk.device, .Graphics)

	// Don't set our present queue yet. We'll wait until the first swapchain is created (main window).
	devvk.present_queue = nil
	devvk.present_index = 0

	devvk.vk_functions = vma.create_vulkan_functions()

	// Create VMA allocator.
	allocator_info := vma.Allocator_Create_Info {
		flags              = {.Buffer_Device_Address},
		physical_device    = refvk.phys_device.physical_device,
		device             = devvk.device.device,
		vulkan_functions   = &devvk.vk_functions,
		instance           = ctxvk.instance.instance,
		vulkan_api_version = vk.API_VERSION_1_4,
	}

	vma_err := vma.create_allocator(allocator_info, &devvk.allocator)
	if vma_err != .SUCCESS {
		fmt.eprintln("Failed to create Allocator! Error:", vma_err)
	}

	device._destroy = device_vk_destroy
}

device_vk_destroy :: proc(device: ^Device) {
	devvk := &device.internal.(Device_Vk)

	vma.destroy_allocator(devvk.allocator)
	vkb.destroy_device(devvk.device)
}
