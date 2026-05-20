package nfx

import "core:fmt"
import "ext/vkb"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"

Device_Reference_Vk :: struct {
	phys_device: ^vkb.Physical_Device,
}

device_reference_vk_destroy :: proc(ref: ^Device_Reference) {
	refvk := &ref.internal.(Device_Reference_Vk)

	vkb.destroy_physical_device(refvk.phys_device)
}

Context_Vk :: struct {
	instance: ^vkb.Instance,
}

context_vk_init :: proc(ctx: ^Context) {
	cvk: Context_Vk

	ibuilder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(ibuilder)

	// TODO: Decide whether to target a lower Vulkan version
	vkb.instance_builder_require_api_version(ibuilder, vk.API_VERSION_1_4)

	when ODIN_DEBUG {
		sys_info, sys_info_err := vkb.get_system_info()

		if sys_info_err != nil {
			fmt.eprintln("Failed to get Vulkan system info! Error:", sys_info_err)
		}

		if sys_info.validation_layers_available {
			vkb.instance_builder_enable_validation_layers(ibuilder)
		}

		if sys_info.debug_utils_available {
			vkb.instance_builder_use_default_debug_messenger(ibuilder)
		}

		vkb.destroy_system_info(sys_info)
	}

	inst_err: vkb.Error
	cvk.instance, inst_err = vkb.instance_builder_build(ibuilder)

	if inst_err != nil {
		fmt.eprintln("Failed to build instance! Error:", inst_err)
		return
	}

	dev_selector := vkb.create_physical_device_selector(cvk.instance)
	defer vkb.destroy_physical_device_selector(dev_selector)

	vkb.physical_device_selector_set_minimum_version(dev_selector, vk.API_VERSION_1_4)
	vkb.physical_device_selector_defer_surface_initialization(dev_selector)

	// Required features.
	req_features := vk.PhysicalDeviceFeatures {
		shaderInt64 = true,
	}
	vkb.physical_device_selector_set_required_features(dev_selector, req_features)
	vkb.physical_device_selector_add_required_extension(
		dev_selector,
		vk.KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME,
	)

	req_features_12 := vk.PhysicalDeviceVulkan12Features {
		bufferDeviceAddress = true,
	}
	vkb.physical_device_selector_set_required_features_12(dev_selector, req_features_12)

	// Prep features list.
	features_14 := vk.PhysicalDeviceVulkan14Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
		pNext = nil,
	}

	features_13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext = &features_14,
	}

	features_12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &features_13,
	}

	features_11 := vk.PhysicalDeviceVulkan11Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &features_12,
	}

	features_2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &features_11,
	}

	dev_list, dev_list_err := vkb.physical_device_selector_select_devices(
		dev_selector,
		context.temp_allocator,
	)
	ctx.devices = make([dynamic]Device_Reference)

	if dev_list_err != nil {
		fmt.eprintln("Failed to create Device List! Error:", dev_list_err)
	}

	for dev, index in dev_list {
		if dev.properties.deviceType == .CPU || dev.properties.deviceType == .OTHER {
			// Skip CPUs and unrecognized devices.
			vkb.destroy_physical_device(dev)
			continue
		}

		if !vkb.physical_device_enable_extension_if_present(dev, vk.KHR_SWAPCHAIN_EXTENSION_NAME) {
			// We need a swapchain.
			// TODO: Allow headless devices.
			vkb.destroy_physical_device(dev)
			continue
		}

		dev_ref: Device_Reference
		dev_ref.name = dev.name

		vkb.physical_device_get_supported_features(dev, &features_2)

		// Populate features
		dev_ref.features += features_2.features.geometryShader ? {.Geometry_Shader} : {}
		dev_ref.features += features_2.features.tessellationShader ? {.Tessellation_Shader} : {}
		dev_ref.features +=
			features_2.features.textureCompressionASTC_LDR ? {.Compression_ASTC_LDR} : {}
		dev_ref.features += features_2.features.textureCompressionBC ? {.Compression_BC} : {}
		dev_ref.features += features_2.features.textureCompressionETC2 ? {.Compression_ETC2} : {}
		dev_ref.features += features_13.textureCompressionASTC_HDR ? {.Compression_ASTC_HDR} : {}

		// Raytracing.
		rt_available := vkb.physical_device_enable_extensions_if_present(
			dev,
			{
				vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
				vk.KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
				vk.KHR_RAY_QUERY_EXTENSION_NAME,
				vk.KHR_PIPELINE_LIBRARY_EXTENSION_NAME,
				vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
			},
		)

		mesh_shader_available := vkb.physical_device_enable_extension_if_present(
			dev,
			vk.EXT_MESH_SHADER_EXTENSION_NAME,
		)

		dev_ref.features += rt_available ? {.Raytracing} : {}
		dev_ref.features += mesh_shader_available ? {.Mesh_Shader} : {}

		dev_ref_int: Device_Reference_Vk
		dev_ref_int.phys_device = dev
		dev_ref.internal = dev_ref_int
		dev_ref.destroy = device_reference_vk_destroy

		#partial switch dev.properties.deviceType {
		case .INTEGRATED_GPU:
			dev_ref.type = .Integrated
		case .DISCRETE_GPU:
			dev_ref.type = .Dedicated
		case .VIRTUAL_GPU:
			dev_ref.type = .Virtual
		}

		append(&ctx.devices, dev_ref)
	}

	ctx.internal = cvk
	ctx.destroy = context_vk_destroy
}

context_vk_destroy :: proc(ctx: ^Context) {
	cvk := &ctx.internal.(Context_Vk)

	for &ref in ctx.devices {
		ref->destroy()
	}

	vkb.destroy_instance(cvk.instance)
	delete(ctx.devices)
}
