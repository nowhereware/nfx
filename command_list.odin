package nfx

Command_List_Internal :: union {
	Command_List_Vk,
}

Command_List :: struct {
	internal: Command_List_Internal,
	device:   ^Device,
	destroy:  proc(list: ^Command_List),
}

command_list_init :: proc(device: ^Device, list: ^Command_List) {
	switch device.ctx.backend {
	case .Vulkan:
		command_list_vk_init(device, list)
	case .DX12:
	case .Metal:
	}

	list.device = device
}
