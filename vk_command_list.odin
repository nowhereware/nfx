package nfx

import "core:fmt"
import vk "vendor:vulkan"

Command_List_Vk :: struct {
	pool:    vk.CommandPool,
	buffers: [dynamic]vk.CommandBuffer,
}

command_list_vk_init :: proc(device: ^Device, list: ^Command_List) {
	dvk := &device.internal.(Device_Vk)
	lvk: Command_List_Vk

	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		pNext            = nil,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = dvk.graphics_index,
	}

	res := vk.CreateCommandPool(dvk.device.device, &pool_info, nil, &lvk.pool)

	if res != .SUCCESS {
		fmt.eprintln("Failed to create Command Pool! Error:", res)
	}

	buffer_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		pNext              = nil,
		commandPool        = lvk.pool,
		level              = .PRIMARY,
		commandBufferCount = device.frame_count,
	}

	lvk.buffers = make([dynamic]vk.CommandBuffer, device.frame_count)

	vk.AllocateCommandBuffers(dvk.device.device, &buffer_info, raw_data(lvk.buffers))

	list.internal = lvk
	list.destroy = command_list_vk_destroy
}

command_list_vk_destroy :: proc(list: ^Command_List) {
	dvk := &list.device.internal.(Device_Vk)
	lvk := &list.internal.(Command_List_Vk)

	vk.FreeCommandBuffers(
		dvk.device.device,
		lvk.pool,
		u32(len(lvk.buffers)),
		raw_data(lvk.buffers),
	)
	vk.DestroyCommandPool(dvk.device.device, lvk.pool, nil)

	delete(lvk.buffers)
}
