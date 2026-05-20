package nfx

import "core:bytes"
import "core:fmt"
import "core:image/qoi"
import "core:math"
import "core:mem"
import "ext/ktx"
import stb "vendor:stb/image"
import vk "vendor:vulkan"

// ## Image
// A CPU-side representation of an Image.
Image :: struct {
	// The internal KTX data of the Texture.
	data:     ^ktx.Texture2,
	// The total size of the image in memory.
	mem_size: uint,
	// The resolution of the base level of the image in pixels. \
	// NOTE: The underlying image may be compressed, so this should not be used for calculating memory
	// size. Instead, use the Image's `mem_size` field, which also takes mip levels into account.
	size:     [2]u32,
	// The number of mip levels of the image. If mipmaps weren't generated, this should be set to 1.
	levels:   u32,
}

@(private)
QOI_MAGIC_NUMBER: []u8 : {'q', 'o', 'i', 'f'}

@(private)
KTX_MAGIC_NUMBER: []u8 : {0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A}

// Loads an image from bytes into an NFX `Image`. Input `data` is copied into the output `image`, so it's safe to
// free `data` without invalidating `image`. If `gen_mipmaps` is set to true, then the `image` will have mipmaps
// generated if they are not already present in the source image.
image_load_from_bytes :: proc(data: []u8, gen_mipmaps: bool, image: ^Image) {
	// Check magic numbers for file format.
	if bytes.compare(data[0:12], KTX_MAGIC_NUMBER) == 0 {
		// KTX file.
		result := ktx.Texture2_CreateFromMemory(
			raw_data(data),
			uint(len(data)),
			{.LOAD_IMAGE_DATA},
			&image.data,
		)

		if result != .SUCCESS {
			fmt.eprintln("Failed to load texture! Error:", result)
		}
	} else if bytes.compare(data[0:4], QOI_MAGIC_NUMBER) == 0 {
		// QOI file.
		qoi_parser(data, image)
	} else {
		// Probably STB file.
		x, y, num_channels, channel_size: i32

		if stb.is_16_bit_from_memory(raw_data(data), i32(len(data))) == 1 {
			channel_size = 2
			img_data := stb.load_16_from_memory(
				raw_data(data),
				i32(len(data)),
				&x,
				&y,
				&num_channels,
				4,
			)

			// Load image into KTX2.
			texture_info := ktx.TextureCreateInfo {
				vkFormat        = .R16G16B16A16_UNORM,
				baseWidth       = u32(x),
				baseHeight      = u32(y),
				baseDepth       = 1,
				numDimensions   = 2,
				numLevels       = 1,
				numFaces        = 1,
				numLayers       = 1,
				isArray         = false,
				generateMipmaps = false,
			}
			result := ktx.Texture2_Create(texture_info, .ALLOC_STORAGE, &image.data)

			if result != .SUCCESS {
				fmt.eprintln("Failed to create KTX texture! Error:", result)
			}

			// Copy image into KTX.
			image.data->SetImageFromMemory(
				0,
				0,
				0,
				cast([^]u8)img_data,
				uint(x * y * num_channels * channel_size),
			)

			stb.image_free(img_data)
		} else {
			channel_size = 1
			img_data := stb.load_from_memory(
				raw_data(data),
				i32(len(data)),
				&x,
				&y,
				&num_channels,
				4,
			)

			// Load image into KTX2.
			texture_info := ktx.TextureCreateInfo {
				vkFormat        = .R8G8B8A8_SRGB,
				baseWidth       = u32(x),
				baseHeight      = u32(y),
				baseDepth       = 1,
				numDimensions   = 2,
				numLevels       = 1,
				numFaces        = 1,
				numLayers       = 1,
				isArray         = false,
				generateMipmaps = false,
			}
			result := ktx.Texture2_Create(texture_info, .ALLOC_STORAGE, &image.data)

			if result != .SUCCESS {
				fmt.eprintln("Failed to create KTX texture! Error:", result)
			}

			// Copy image into KTX.
			image.data->SetImageFromMemory(
				0,
				0,
				0,
				img_data,
				uint(x * y * num_channels * channel_size),
			)

			stb.image_free(img_data)
		}
	}

	// Generate mipmaps if necessary.
	if gen_mipmaps {
		if image.data.numLevels == 1 {
			// Generate mipmaps.
			if !image.data->NeedsTranscoding() {
				if image.data.vkFormat != .R8G8B8A8_SRGB {
					// Image is in ASTC, decode.
					result := ktx.Texture2_DecodeAstc(image.data)

					if result != .SUCCESS {
						fmt.println("Failed to decode texture data! Error:", result)
					}
				}
			} else {
				result := ktx.Texture2_TranscodeBasis(image.data, .RGBA32, {.HIGH_QUALITY})

				if result != .SUCCESS {
					fmt.eprintln("Failed to convert Texture to uncompressed! Error:", result)
				}
			}

			x := i32(image.data.baseWidth)
			y := i32(image.data.baseHeight)
			num_channels: i32 = 4
			image.levels = u32(math.floor(math.log2(f32(max(x, y))))) + 1

			// Allocate a new Texture sized to fit our desired mip levels.
			tex_info := ktx.TextureCreateInfo {
				baseWidth       = image.data.baseWidth,
				baseHeight      = image.data.baseHeight,
				baseDepth       = image.data.baseDepth,
				numDimensions   = image.data.numDimensions,
				numLevels       = image.levels,
				numFaces        = image.data.numFaces,
				numLayers       = image.data.numLayers,
				isArray         = image.data.isArray,
				pDfd            = image.data.pDfd,
				vkFormat        = image.data.vkFormat,
				generateMipmaps = true,
			}

			new_tex: ^ktx.Texture2
			result := ktx.Texture2_Create(tex_info, .ALLOC_STORAGE, &new_tex)

			if result != .SUCCESS {
				fmt.eprintln("Failed to allocate newly sized KTX! Error:", result)
			}

			// Write base image.
			result = new_tex->SetImageFromMemory(
				0,
				0,
				0,
				image.data.pData,
				uint(x * y * num_channels),
			)

			if result != .SUCCESS {
				fmt.eprintln("Failed to set layer 0! Error:", result)
			}

			// Copy our base image into a temp copy.
			temp_image := make([dynamic]u8, new_tex->GetImageSize(0), context.temp_allocator)
			mem.copy_non_overlapping(raw_data(temp_image), new_tex.pData, len(temp_image))

			power: u32 = 2
			for i: u32 = 1; i < image.levels; i += 1 {
				level_width := u32(x) / power
				level_height := u32(y) / power
				level_size := level_width * level_height * u32(num_channels)
				level_buffer := make([dynamic]u8, level_size, context.temp_allocator)

				// Create a resized image and upload to texture for each level.
				stb_result := stb.resize_uint8(
					raw_data(temp_image),
					x,
					y,
					x * num_channels,
					raw_data(level_buffer),
					i32(level_width),
					i32(level_height),
					i32(level_width) * num_channels,
					num_channels,
				)

				if stb_result == 0 {
					fmt.eprintln("Failed to resize image! Error:", stb.failure_reason())
				}

				// Upload to KTX.
				result = new_tex->SetImageFromMemory(
					i,
					0,
					0,
					raw_data(level_buffer),
					len(level_buffer),
				)

				if result != .SUCCESS {
					fmt.eprintln("Failed to load mip level", i, "into KTX image! Error:", result)
				}

				power *= 2
			}

			// Delete old texture and replace it with mipmapped texture.
			image.data->Destroy()
			image.data = new_tex
		}
	}

	image.data.generateMipmaps = false

	// Compress texture into UASTC for future usage.
	basis_params := ktx.BasisParams {
		structSize       = u32(size_of(ktx.BasisParams)),
		uastc            = true,
		compressionLevel = 2,
		qualityLevel     = 128,
	}

	result := ktx.Texture2_CompressBasisEx(image.data, &basis_params)

	if result != .SUCCESS {
		fmt.eprintln("Failed to convert texture into UASTC! Error:", result)
	}

	image.size.x = image.data.baseWidth
	image.size.y = image.data.baseHeight
	image.levels = image.data.numLevels

	// DEBUG Print
	fmt.println("X:", image.size.x, "Y:", image.size.y, "Levels:", image.levels)
}

image_load :: proc {
	image_load_from_bytes,
}

// Destroys a given Image's underlying data. If an Image has been uploaded to a Buffer, this does *not*
// invalidate the Buffer.
image_destroy :: proc(image: ^Image) {
	image.data->Destroy()
}

// Compresses the image into a desired format. To get the best available compressed format supported on the
// current Device, use `device_get_optimal_image_format`.
image_compress :: proc(image: ^Image, format: ktx.Transcode_Format) {
	result := ktx.Texture2_TranscodeBasis(image.data, format, {.HIGH_QUALITY})

	if result != .SUCCESS {
		fmt.eprintln("Failed to transcode image to format", format, ": Error:", result)
	}
}

// Gets the byte size of an entire Image, including all levels.
image_get_size :: proc(image: ^Image) -> uint {
	accum: uint = 0

	for i: u32 = 0; i < image.levels; i += 1 {
		accum += image.data->GetImageSize(i)
	}

	return accum
}

// Gets the byte size of a given level of an Image.
image_get_level_size :: proc(image: ^Image, level: u32) -> uint {
	return image.data->GetImageSize(level)
}

// Platform implementations.

@(private)
// Uploads a given slice of raw QOI data into an Image.
qoi_parser :: proc(data: []u8, image: ^Image) {
	options := qoi.Options{.alpha_add_if_missing}

	qoi_img, error := qoi.load_from_bytes(data, options)

	if error != nil {
		fmt.eprintln("Failed to load QOI image! Error:", error)
	}

	// Upload to KTX image.
	texture_info := ktx.TextureCreateInfo {
		vkFormat        = .R8G8B8A8_SRGB,
		baseWidth       = cast(u32)qoi_img.width,
		baseHeight      = cast(u32)qoi_img.height,
		baseDepth       = 1,
		numDimensions   = 2,
		numLevels       = 1,
		numFaces        = 1,
		numLayers       = 1,
		isArray         = false,
		generateMipmaps = false,
	}
	result := ktx.Texture2_Create(texture_info, .ALLOC_STORAGE, &image.data)

	if result != .SUCCESS {
		fmt.eprintln("Failed to create KTX texture! Error:", result)
	}

	// Copy image into KTX.
	image.data->SetImageFromMemory(
		0,
		0,
		0,
		&qoi_img.pixels.buf[0],
		uint(qoi_img.width * qoi_img.height * 4),
	)

	qoi.destroy(qoi_img)
}
