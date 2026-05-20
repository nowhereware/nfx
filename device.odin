package nfx

import "core:fmt"
import "core:sync"
import "ext/ktx"

Device_Internal :: union {
	Device_Vk,
}

// ## Device
// Represents a logical interface for a graphics device.
Device :: struct {
	internal:      Device_Internal,
	ctx:           ^Context,
	// The Device Reference of this Device.
	ref:           Device_Reference,
	// The total count of frames in flight. Should not be modified after device creation.
	frame_count:   u32,
	// The index of the frame in flight currently being written to.
	frame_index:   u32,
	// A list of queued Buffers to be deleted. Buffers are submitted to this queue on their given frame,
	// and are deleted once the specific frame index is reached again, indicating the buffer is no longer
	// in use.
	delete_queues: [dynamic][dynamic]Buffer,
	// Mutex for delete queues.
	queue_mutex:   sync.Atomic_Mutex,
	// Modifies the frame index and performs and queued Buffer deletions. Should only be run once per
	// frame, at the very end.
	end_frame:     proc(dev: ^Device),
	// Internal proc to delete the device. Should not be called directly, instead call `device_destroy`.
	_destroy:      proc(dev: ^Device),
}

// Creates a new Device, selecting a device automatically or from a manually passed reference. Also
// optionally takes in a `frame_count`, which controls the count of frames in flight.
device_init :: proc(
	ctx: ^Context,
	device: ^Device,
	frame_count: u32 = 2,
	ref: Maybe(^Device_Reference) = nil,
) {
	device.ctx = ctx
	dev_ref: ^Device_Reference = nil
	if ref != nil {
		dev_ref = ref.(^Device_Reference)
	} else {
		// Choose device based on features.
		max_r: ^Device_Reference = &ctx.devices[0]
		max_score: int = 0
		for &r in ctx.devices {
			current_score: int = 0
			if r.type == .Dedicated {
				// Bonus points.
				current_score += 50
			}

			for feat in r.features {
				current_score += 25
			}

			if current_score > max_score {
				max_r = &r
				max_score = current_score
			}
		}

		dev_ref = max_r
	}

	fmt.println("Chosen device:", dev_ref.name)
	device.frame_count = frame_count

	switch ctx.backend {
	case .Vulkan:
		device_vk_init(ctx, dev_ref, device)
	case .DX12:
	case .Metal:
	}

	device.delete_queues = make([dynamic][dynamic]Buffer, frame_count)

	for i in 0 ..< frame_count {
		device.delete_queues[i] = make([dynamic]Buffer)
	}

	device.ref = dev_ref^
}

device_destroy :: proc(device: ^Device) {
	for &queue in device.delete_queues {
		// Clear out queue.
		for &buff in queue {
			buff->_destroy()
		}
		delete(queue)
	}
	delete(device.delete_queues)

	device->_destroy()
}

device_get_optimal_image_format :: proc(device: ^Device) -> ktx.Transcode_Format {
	if .Compression_ASTC_LDR in device.ref.features {
		return .ASTC_4x4_RGBA
	}

	if .Compression_BC in device.ref.features {
		return .BC7_RGBA
	}

	if .Compression_ETC2 in device.ref.features {
		return .ETC2_RGBA
	}

	return .RGBA32
}

device_end_frame :: proc(device: ^Device) {
	device.frame_index += 1
	device.frame_index = device.frame_index % device.frame_count

	// Clear out queued Buffers.
	for &buff in device.delete_queues[device.frame_index] {
		// Delete the buffer.
	}
}
