package nfx

import "core:fmt"
import "core:mem"
import "ext/vma"
import vk "vendor:vulkan"

Buffer_Vk :: struct {
	buffer:     vk.Buffer,
	allocation: vma.Allocation,
	alloc_info: vma.Allocation_Info,
}

buffer_vk_init :: proc(device: ^Device, type: Buffer_Type, size: u32, buffer: ^Buffer) {
	dvk := &device.internal.(Device_Vk)
	bvk: Buffer_Vk

	alloc_info := vma.Allocation_Create_Info {
		flags = vma_convert_buffer_create_flags(type),
		usage = .Auto,
	}

	buffer_info := vk.BufferCreateInfo {
		sType                 = .BUFFER_CREATE_INFO,
		pNext                 = nil,
		flags                 = {},
		size                  = cast(vk.DeviceSize)size,
		usage                 = vk_convert_buffer_usage(type),
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = 1,
		pQueueFamilyIndices   = &dvk.graphics_index,
	}

	err := vma.create_buffer(
		dvk.allocator,
		buffer_info,
		alloc_info,
		&bvk.buffer,
		&bvk.allocation,
		&bvk.alloc_info,
	)

	if err != .SUCCESS {
		fmt.eprintln("Failed to create Buffer! Error:", err)
	}

	alloc_props: vk.MemoryPropertyFlags
	vma.get_allocation_memory_properties(dvk.allocator, bvk.allocation, &alloc_props)

	if .HOST_VISIBLE not_in alloc_props {
		buffer.write_type = .Staged
	} else {
		buffer.write_type = .Direct
	}

	buffer.internal = bvk
	buffer._destroy = buffer_vk_destroy
	buffer.write = buffer_vk_write
}

buffer_vk_destroy :: proc(buffer: ^Buffer) {
	bvk := &buffer.internal.(Buffer_Vk)
	dvk := &buffer.device.internal.(Device_Vk)

	vma.destroy_buffer(dvk.allocator, bvk.buffer, bvk.allocation)
}

buffer_vk_write :: proc(
	buffer: ^Buffer,
	list: ^Command_List,
	offset: u32,
	data: rawptr,
	size: u32,
) {
	bvk := &buffer.internal.(Buffer_Vk)
	dvk := &buffer.device.internal.(Device_Vk)
	lvk := &list.internal.(Command_List_Vk)

	if buffer.write_type == .Direct {
		staging_address := rawptr(uintptr(bvk.alloc_info.mapped_data) + uintptr(offset))
		mem.copy_non_overlapping(staging_address, data, int(size))
	} else {
		if buffer.temp_staging == nil {
			// Create staging buffer sized to our data size.
			tmp_buff := new(Buffer)
			buffer_init(buffer.device, .Staging, size, tmp_buff)
			buffer.temp_staging = tmp_buff
		}

		temp_buff := buffer.temp_staging

		if temp_buff.size < size {
			// Create new resized temporary buffer.
			buffer_destroy(temp_buff)
			free(temp_buff)

			new_temp_buff := new(Buffer)
			buffer_init(buffer.device, .Staging, size, new_temp_buff)
			buffer.temp_staging = new_temp_buff
			temp_buff = buffer.temp_staging
		}

		tvk := &temp_buff.internal.(Buffer_Vk)

		staging_address := rawptr(uintptr(tvk.alloc_info.mapped_data) + uintptr(offset))
		mem.copy_non_overlapping(staging_address, data, int(size))
		current_buff := lvk.buffers[buffer.device.frame_index]

		copy_region := vk.BufferCopy2 {
			sType     = .BUFFER_COPY_2,
			pNext     = nil,
			srcOffset = 0,
			dstOffset = cast(vk.DeviceSize)offset,
			size      = cast(vk.DeviceSize)size,
		}

		copy_info := vk.CopyBufferInfo2 {
			sType       = .COPY_BUFFER_INFO_2,
			pNext       = nil,
			srcBuffer   = tvk.buffer,
			dstBuffer   = bvk.buffer,
			regionCount = 1,
			pRegions    = &copy_region,
		}

		vk.CmdCopyBuffer2(current_buff, &copy_info)
	}
}

@(private = "file")
vk_convert_buffer_usage :: proc(type: Buffer_Type) -> (out: vk.BufferUsageFlags) {
	switch type {
	case .Vertex:
		out = {.TRANSFER_SRC, .TRANSFER_DST, .VERTEX_BUFFER}
	case .Index:
		out = {.TRANSFER_SRC, .TRANSFER_DST, .INDEX_BUFFER}
	case .Storage:
		out = {.TRANSFER_SRC, .TRANSFER_DST, .STORAGE_BUFFER}
	case .Uniform:
		out = {.TRANSFER_SRC, .TRANSFER_DST, .UNIFORM_BUFFER}
	case .Staging:
		out = {.TRANSFER_SRC, .TRANSFER_DST, .STORAGE_BUFFER}
	}

	return out
}

@(private = "file")
vma_convert_buffer_create_flags :: proc(type: Buffer_Type) -> (out: vma.Allocation_Create_Flags) {
	switch type {
	case .Vertex:
		out = {.Mapped, .Host_Access_Sequential_Write, .Host_Access_Allow_Transfer_Instead}
	case .Index:
		out = {.Mapped, .Host_Access_Sequential_Write, .Host_Access_Allow_Transfer_Instead}
	case .Storage:
		out = {.Mapped, .Host_Access_Sequential_Write, .Host_Access_Allow_Transfer_Instead}
	case .Uniform:
		out = {.Mapped, .Host_Access_Random}
	case .Staging:
		out = {.Mapped, .Host_Access_Sequential_Write}
	}

	return out
}
