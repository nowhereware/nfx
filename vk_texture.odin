package nfx

import "core:fmt"
import "ext/vma"
import vk "vendor:vulkan"

Texture_Vk :: struct {
	image:      vk.Image,
	image_view: vk.ImageView,
	allocation: vma.Allocation,
	alloc_info: vma.Allocation_Info,
}

texture_vk_init :: proc(device: ^Device, info: Texture_Create_Info, texture: ^Texture) {
	dvk := &device.internal.(Device_Vk)
	tvk: Texture_Vk

	layer_count := info.type == .D2 ? 1 : info.layers
	image_create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		pNext = nil,
		imageType = vk_convert_texture_type(info.type),
		format = vk_convert_format(info.format),
		extent = vk.Extent3D{width = info.size.x, height = info.size.y, depth = info.size.z},
		mipLevels = info.mip_levels,
		arrayLayers = layer_count,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = vk_convert_image_usage(info.usage),
		sharingMode = .EXCLUSIVE,
		queueFamilyIndexCount = 1,
		pQueueFamilyIndices = &dvk.graphics_index,
		initialLayout = .UNDEFINED,
	}

	allocation_create_info := vma.Allocation_Create_Info {
		flags = {.Dedicated_Memory},
		usage = .Auto,
	}

	res := vma.create_image(
		dvk.allocator,
		image_create_info,
		allocation_create_info,
		&tvk.image,
		&tvk.allocation,
		&tvk.alloc_info,
	)

	if res != .SUCCESS {
		fmt.eprintln("Failed to create Vulkan image for texture! Error:", res)
	}

	texture.internal = tvk
}

@(private = "file")
vk_convert_texture_type :: proc(type: Texture_Type) -> (out: vk.ImageType) {
	switch type {
	case .D2:
		out = .D2
	case .D2_Array:
		out = .D2
	case .D3:
		out = .D3
	}

	return out
}

@(private)
vk_convert_format :: proc(format: Texture_Format) -> (out: vk.Format) {
	switch format {
	case .R8_UNORM:
		out = .R8_UNORM
	case .RG8_UNORM:
		out = .R8G8_UNORM
	case .RGB8_UNORM:
		out = .R8G8B8_UNORM
	case .RGBA8_UNORM:
		out = .R8G8B8A8_UNORM
	case .R10G10B10A2_UNORM:
		out = .A2R10G10B10_UNORM_PACK32
	case .RGBA8_SRGB:
		out = .R8G8B8A8_SRGB
	case .ASTC:
		out = .ASTC_6x6_UNORM_BLOCK
	case .BC7:
		out = .BC7_UNORM_BLOCK
	case .ETC2:
		out = .ETC2_R8G8B8A8_UNORM_BLOCK
	}

	return out
}

@(private)
vk_convert_image_usage :: proc(flags: Texture_Usage_Flags) -> (out: vk.ImageUsageFlags) {
	for flag in flags {
		switch flag {
		case .Sampled:
			out += {.SAMPLED}
		case .Storage:
			out += {.STORAGE}
		case .Transfer_Src:
			out += {.TRANSFER_SRC}
		case .Transfer_Dst:
			out += {.TRANSFER_DST}
		case .Color_Attach:
			out += {.COLOR_ATTACHMENT}
		case .Depth_Stencil_Attach:
			out += {.DEPTH_STENCIL_ATTACHMENT}
		}
	}

	return out
}
