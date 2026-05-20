package nfx

import "core:sync"

Buffer_Internal :: union {
	Buffer_Vk,
}

// ## Buffer Type
// The desired functionality of the Buffer. Under the hood, there isn't really a difference in memory
// layout for Buffer types, the only potential difference is in the host visibility of the Buffer. All
// Buffer types are ideally host-visible, however only the `Uniform` and `Staging` buffer types are
// *guaranteed* to be host-visible. Depending on the host system's capabilities, Buffers marked
// `Vertex`, `Index`, or `Storage` may end up in a non host-visible format for performance.
Buffer_Type :: enum {
	Vertex,
	Index,
	Storage,
	Uniform,
	Staging,
}

// ## Buffer Write Type
// The write type of a Buffer. If set to `Direct`, then the buffer is host-visible and may be directly
// written to by the CPU. If set to `Staged`, then the buffer is not host-visible and must be written
// to via a buffer copy. Writes may still be performed "directly" to both buffers, however if a buffer
// has the `Staged` write type then a temporary Staging buffer will be used under the hood. As such,
// it may be beneficial to batch writes into a separate Staging buffer and perform a copy on the GPU
// timeline if the buffer has a `Staged` write type, rather than allowing the buffer to perform multiple
// Staging buffer creations under the hood and potentially cause rather severe performance degradation.
Buffer_Write_Type :: enum {
	Direct,
	Staged,
}

Buffer :: struct {
	internal:     Buffer_Internal,
	device:       ^Device,
	type:         Buffer_Type,
	write_type:   Buffer_Write_Type,
	// A temporary staging buffer, used if the buffer's `write_type` is `.Staged`.
	temp_staging: ^Buffer,
	// The current allocated size of the buffer.
	size:         u32,
	// Writes the amount of data pointed to by `data` and `size` to the region of the buffer offset
	// by `offset`.
	write:        proc(buffer: ^Buffer, list: ^Command_List, offset: u32, data: rawptr, size: u32),
	// Internal proc to destroy the Buffer. Should not be called directly, instead use `buffer_destroy`.
	_destroy:     proc(buffer: ^Buffer),
}

buffer_init :: proc(device: ^Device, type: Buffer_Type, size: u32, buffer: ^Buffer) {
	switch device.ctx.backend {
	case .Vulkan:
		buffer_vk_init(device, type, size, buffer)
	case .DX12:
	case .Metal:
	}

	buffer.type = type
	buffer.device = device
	buffer.size = size
}

buffer_destroy :: proc(buffer: ^Buffer) {
	// Queues up the buffer for deletion.
	sync.lock(&buffer.device.queue_mutex)
	append(&buffer.device.delete_queues[buffer.device.frame_index], buffer^)
	sync.unlock(&buffer.device.queue_mutex)
}
