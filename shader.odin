package nfx

import "core:bytes"
import "core:fmt"
import spv "ext/spirv_cross"

@(private)
// Magic number is stored as little-endian representation for quick reading, even though the original format
// is actually big-endian.
SPIRV_MAGIC_NUMBER: []u8 : {03, 02, 23, 07}

Shader_Internal :: union {}

Shader :: struct {
	internal: Shader_Internal,
}

shader_load_from_bytes :: proc(device: ^Device, data: []u8, shader: ^Shader) {
	// Check if SPIR-V magic number exists, assume Slang otherwise.
	if bytes.equal(data[0:4], SPIRV_MAGIC_NUMBER) {
		// SPIR-V.
		spvctx: spv.Context
		res := spv.context_create(&spvctx)

		if res != .SUCCESS {
			fmt.eprintln("Failed to create SPIRV context! Error:", spvctx)
		}
	} else {
		// Probably Slang.
	}
}
