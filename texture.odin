package nfx

Texture_Internal :: union {
	Texture_Vk,
}

Texture_Type :: enum {
	D2,
	D2_Array,
	D3,
}

Texture_Usage_Flag :: enum {
	Sampled,
	Storage,
	Transfer_Src,
	Transfer_Dst,
	Color_Attach,
	Depth_Stencil_Attach,
}
Texture_Usage_Flags :: bit_set[Texture_Usage_Flag]

// ## Texture Format
// The data format of a texture. Format naming is interpreted as follows: formats with several components
// followed by a single number X are interpreted as having that X bits for each component. Otherwise, the
// number of bits for each component immediately follows the component's identifier.
Texture_Format :: enum {
	R8_UNORM,
	RG8_UNORM,
	RGB8_UNORM,
	RGBA8_UNORM,
	R10G10B10A2_UNORM,
	RGBA8_SRGB,
	ASTC,
	BC7,
	ETC2,
}

Texture :: struct {
	internal: Texture_Internal,
	upload:   proc(texture: ^Texture, buffer: ^Buffer),
	_destroy: proc(texture: ^Texture),
}

Texture_Create_Info :: struct {
	type:       Texture_Type,
	usage:      Texture_Usage_Flags,
	// The dimensions of the Texture.
	size:       [3]u32,
	format:     Texture_Format,
	mip_levels: u32,
	// The layer count of the image, given the image is 2D or 3D.
	layers:     u32,
}

// Initializes a Texture object in memory. Note that this only prepares the Texture, to upload data to the Texture
// you must first upload data to a separate Buffer, then copy the Buffer to the Texture.
texture_init :: proc(device: ^Device, info: Texture_Create_Info, texture: ^Texture) {
	switch device.ctx.backend {
	case .Vulkan:
		texture_vk_init(device, info, texture)
	case .DX12:
	case .Metal:
	}
}

texture_destroy :: proc(texture: ^Texture) {

}
