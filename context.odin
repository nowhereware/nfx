package nfx

Context_Internal :: union {
	Context_Vk,
}

// ## Backend Type
// The backend type of the NFX Context.
Backend_Type :: enum {
	Vulkan,
	DX12,
	Metal,
}

// ## Device Feature
Device_Feature :: enum {
	Geometry_Shader,
	Tessellation_Shader,
	Compression_ASTC_LDR,
	Compression_BC,
	Compression_ETC2,
	Compression_ASTC_HDR,
	Raytracing,
	Mesh_Shader,
}
Device_Features :: bit_set[Device_Feature]

Device_Type :: enum {
	Dedicated,
	Integrated,
	Virtual,
}

Device_Reference_Internal :: union {
	Device_Reference_Vk,
}

// ## Device Reference
// Stores basic information about a given physical Device. These devices are not implicitly ready for usage,
// to use a given device it can be explicitly passed at Device creation.
Device_Reference :: struct {
	internal: Device_Reference_Internal,
	name:     string,
	features: Device_Features,
	type:     Device_Type,
	destroy:  proc(ref: ^Device_Reference),
}

// ## Context
// Stores information regarding the core of the graphics API. To create a `Context`, pass a pointer to an uninitialized
// `Context` into `context_init()`. The provided `Context` will be populated with information including a list of
// available devices on the user's system via `Device_Reference`s, which subsequently can be used to create a `Device`
// to interact with the given graphics device.
Context :: struct {
	internal: Context_Internal,
	backend:  Backend_Type,
	devices:  [dynamic]Device_Reference,
	// Destroys the Context, including all Device References.
	destroy:  proc(ctx: ^Context),
}

context_init :: proc(ctx: ^Context, preferred_backend: Maybe(Backend_Type) = nil) {
	when ODIN_OS == .Windows {
		if preferred_backend != nil && preferred_backend != .Metal {
			ctx.backend = preferred_backend.(Backend_Type)
		} else {
			// TODO: Implement DX12 and prefer on Windows
			ctx.backend = .Vulkan
		}
	} else when ODIN_OS == .Linux {
		ctx.backend = .Vulkan
	} else when ODIN_OS == .Darwin {
		ctx.backend = .Metal
	}

	switch ctx.backend {
	case .Vulkan:
		context_vk_init(ctx)
	case .DX12:
	case .Metal:
	}
}
