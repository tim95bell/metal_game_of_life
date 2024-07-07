
import Metal
import MetalKit
import simd

// MARK: functions to help with generating inner radius and outer radius indices
func add_first_case(indices: inout [(UInt32, UInt32)], a: UInt32, board_cell_count_1d: UInt32) {
    // b is zero
    let neg_a: UInt32 = board_cell_count_1d - a
    
    // -a, b
    indices.append((neg_a, 0))
    // a, b
    indices.append((a, 0))
    // b, -a
    indices.append((0, neg_a))
    // b, a
    indices.append((0, a))
}

func add_middle_case(indices: inout [(UInt32, UInt32)], a: UInt32, b: UInt32, board_cell_count_1d: UInt32) {
    let neg_a = board_cell_count_1d - a
    let neg_b = board_cell_count_1d - b
        
    // -a, -b
    indices.append((neg_a, neg_b))
    // -a, b
    indices.append((neg_a, b))
    // a, -b
    indices.append((a, neg_b))
    // a, b
    indices.append((a, b))

    // -b, -a
    indices.append((neg_b, neg_a))
    // -b, a
    indices.append((neg_b, a))
    // b, -a
    indices.append((b, neg_a))
    // b, a
    indices.append((b, a))
}

func add_last_case(indices: inout [(UInt32, UInt32)], a_and_b: UInt32, board_cell_count_1d: UInt32) {
    let neg_a_and_b = board_cell_count_1d - a_and_b
        
    // -a, -b
    indices.append((neg_a_and_b, neg_a_and_b))
    // -a, b
    indices.append((neg_a_and_b, a_and_b))
    // a, -b
    indices.append((a_and_b, neg_a_and_b))
    // a, b
    indices.append((a_and_b, a_and_b))
}

// MARK: SmoothLifeRenderer

enum UpdateMode {
    case none, step, run
}

class SmoothLifeRenderer: NSObject, MTKViewDelegate {
    
    var uniforms: SmoothLifeUniforms
    var device: MTLDevice
    var command_queue: MTLCommandQueue
    var library: MTLLibrary
    var vertex_function: MTLFunction
    var fragment_function: MTLFunction
    var update_function: MTLFunction
    var render_pipeline_state: MTLRenderPipelineState?
    var compute_pipeline_state: MTLComputePipelineState?
    var uniforms_buffer: MTLBuffer
    var vertex_buffer: MTLBuffer
    var radius_index_buffer: MTLBuffer
    var data_buffer_output_index: Int
    var data_buffer: [MTLBuffer]
    var camera_position: simd_float3
    let near_plane: Float
    let far_plane: Float
    let fov: Float
    var update_mode: UpdateMode
    var update_on_gpu: Bool
    
    func play_or_pause_update() {
        if (self.update_mode == UpdateMode.run) {
            update_mode = UpdateMode.none
        } else {
            update_mode = UpdateMode.run
        }
    }
    
    func one_update() {
        update_mode = UpdateMode.step
    }
    
    func drawable_size_changed(drawable_size: CGSize) {
        uniforms.projection_matrix = calculate_projection_view_matrix(drawable_size: drawable_size, camera_position: camera_position, near_plane: near_plane, far_plane: far_plane, board_cell_count_1d: uniforms.board_cell_count_1d)
        uniforms_buffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout.stride(ofValue: uniforms))
    }

    init?(metalKitView: MTKView) {
        self.fov = 1.0/4.0
        self.update_mode = UpdateMode.none
        self.update_on_gpu = true
        
        let board_cell_count_1d: UInt32 = 1000
        let inner_radius: UInt8 = 2
        let outer_radius: UInt8 = 6
        self.far_plane = ((Float(board_cell_count_1d) / 2.0) / tan(fov / 2.0)) * 2.0;
        self.near_plane = (1.0 / 2.0) / tan(fov / 2.0);
        
        camera_position = simd_float3((Float(board_cell_count_1d) / 2.0), (Float(board_cell_count_1d) / 2.0), -(far_plane / 2.0))
        
        var inner_radius_indices: [(UInt32, UInt32)] = [(UInt32, UInt32)]()
        var outer_radius_indices: [(UInt32, UInt32)] = [(UInt32, UInt32)]()

        let inner_radius_squared = inner_radius * inner_radius
        let outer_radius_squared = outer_radius * outer_radius
    outer: for a: UInt32 in 1..<UInt32(outer_radius + 1) {
            // first case, where b is zero
            do {
                let square_len = a * a
                if (square_len <= inner_radius_squared) {
                    add_first_case(indices: &inner_radius_indices, a: a, board_cell_count_1d: board_cell_count_1d)
                } else {
                    // magnitude must always be <= outer_radius
                    assert(square_len <= outer_radius_squared)
                    add_first_case(indices: &outer_radius_indices, a: a, board_cell_count_1d: board_cell_count_1d)
                }
            }

            // middle cases, where a > 0 && b > 0 && a != b
            for b in 1..<a {
                 let square_len = a * a + b * b
                 if (square_len <= inner_radius_squared) {
                     add_middle_case(indices: &inner_radius_indices, a: a, b: b, board_cell_count_1d: board_cell_count_1d)
                 } else if (square_len <= outer_radius_squared) {
                     add_middle_case(indices: &outer_radius_indices, a: a, b: b, board_cell_count_1d: board_cell_count_1d)
                 } else {
                     continue outer
                 }
            }

            // last case, where a == b
            do {
                let square_len = a * a * 2
                if (square_len <= inner_radius_squared) {
                    add_last_case(indices: &inner_radius_indices, a_and_b: a, board_cell_count_1d: board_cell_count_1d)
                } else if (square_len <= outer_radius_squared) {
                    add_last_case(indices: &outer_radius_indices, a_and_b: a, board_cell_count_1d: board_cell_count_1d)
                }
            }
        }

        self.uniforms = SmoothLifeUniforms(projection_matrix: calculate_projection_view_matrix(drawable_size: metalKitView.drawableSize, camera_position: camera_position, near_plane: near_plane, far_plane: far_plane, board_cell_count_1d: board_cell_count_1d), board_cell_count_1d: board_cell_count_1d, inner_radius_cell_count: UInt32(inner_radius_indices.count), outer_radius_cell_count: UInt32(outer_radius_indices.count), inner_radius: inner_radius, outer_radius: outer_radius)
        
        self.device = metalKitView.device!
        self.command_queue = self.device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!
        self.vertex_function = library.makeFunction(name: "smooth_life_vertex")!
        self.fragment_function = library.makeFunction(name: "smooth_life_fragment")!
        self.update_function = library.makeFunction(name: "smooth_life_update")!
        
        let render_pipeline_state_descriptor = MTLRenderPipelineDescriptor()
        render_pipeline_state_descriptor.vertexFunction = vertex_function
        render_pipeline_state_descriptor.fragmentFunction = fragment_function
        render_pipeline_state_descriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        do {
            self.render_pipeline_state = try device.makeRenderPipelineState(descriptor: render_pipeline_state_descriptor)
        } catch {
            print("Failed to create render pipeline state")
        }
        
        self.uniforms_buffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout.stride(ofValue: uniforms), options: MTLResourceOptions.storageModeShared)!
        
        let vertices: [SmoothLifeVertexIn] = [
            SmoothLifeVertexIn(position: simd_float2(1.0, 0.0)),
            SmoothLifeVertexIn(position: simd_float2(1.0, 1.0)),
            SmoothLifeVertexIn(position: simd_float2(0.0,  0.0)),
            SmoothLifeVertexIn(position: simd_float2(0.0,  1.0))
        ]
        self.vertex_buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout.stride(ofValue: vertices[0]), options: MTLResourceOptions.storageModeShared)!
        
        self.data_buffer_output_index = 0
        
        var buffer_a_and_b_data: [SmoothLifeData] = [SmoothLifeData](repeating: 0, count: Int(board_cell_count_1d * board_cell_count_1d));
        for c in 0..<uniforms.board_cell_count_1d / 2 {
            for r in 0..<uniforms.board_cell_count_1d / 2 {
                let index = r * board_cell_count_1d + c
                buffer_a_and_b_data[Int(index)] = Float.random(in: 0...1)
                
            }
        }
        self.data_buffer = [
            device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!,
            device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!
        ]
        
        do {
            self.compute_pipeline_state = try device.makeComputePipelineState(function: update_function)
        } catch {
            print("Failed to create compute pipeline state")
        }
        
        self.radius_index_buffer = device.makeBuffer(length: (inner_radius_indices.count + outer_radius_indices.count) * MemoryLayout.stride(ofValue: inner_radius_indices[0]), options: MTLResourceOptions.storageModeShared)!
        radius_index_buffer.contents().copyMemory(from: inner_radius_indices, byteCount: inner_radius_indices.count * MemoryLayout.stride(ofValue: inner_radius_indices[0]))
        radius_index_buffer.contents().advanced(by: inner_radius_indices.count * MemoryLayout.stride(ofValue: inner_radius_indices[0])).copyMemory(from: outer_radius_indices, byteCount: outer_radius_indices.count * MemoryLayout.stride(ofValue: outer_radius_indices[0]))
    
        super.init()
    }

    func draw(in view: MTKView) {
        let command_buffer = self.command_queue.makeCommandBuffer()!
        
        let render_pass_descriptor = view.currentRenderPassDescriptor!
        render_pass_descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
        let render_encoder = command_buffer.makeRenderCommandEncoder(descriptor: render_pass_descriptor)!
        render_encoder.setRenderPipelineState(self.render_pipeline_state!)
        render_encoder.setVertexBuffer(vertex_buffer, offset: 0, index: SmoothLifeVertexBufferIndex.vertices.rawValue)
        render_encoder.setVertexBuffer(uniforms_buffer, offset: 0, index: SmoothLifeVertexBufferIndex.uniforms.rawValue)
        // use the data buffer that will be the input to the update shader
        render_encoder.setVertexBuffer(data_buffer[1 - data_buffer_output_index], offset: 0, index: SmoothLifeVertexBufferIndex.data.rawValue)
        render_encoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d))
        render_encoder.endEncoding()
        
        let drawable = view.currentDrawable!
        command_buffer.present(drawable, afterMinimumDuration: 1.0/60.0)
        
        if (update_mode != UpdateMode.none) {
            if (update_mode == UpdateMode.step) {
                update_mode = UpdateMode.none
            }
            
            if (update_on_gpu) {
                let compute_command_encoder = command_buffer.makeComputeCommandEncoder()!
                compute_command_encoder.setComputePipelineState(compute_pipeline_state!)
                compute_command_encoder.setBuffer(uniforms_buffer, offset: 0, index: SmoothLifeUpdateBufferIndex.uniforms.rawValue)
                compute_command_encoder.setBuffer(data_buffer[data_buffer_output_index], offset: 0, index: SmoothLifeUpdateBufferIndex.dataOut.rawValue)
                compute_command_encoder.setBuffer(data_buffer[1 - data_buffer_output_index], offset: 0, index: SmoothLifeUpdateBufferIndex.dataIn.rawValue)
                compute_command_encoder.setBuffer(radius_index_buffer, offset: 0, index: SmoothLifeUpdateBufferIndex.radiusIndex.rawValue)
                let cell_count = Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d)
                let grid_size = MTLSizeMake(cell_count, 1, 1)
                var thread_group_size_x = compute_pipeline_state!.maxTotalThreadsPerThreadgroup
                if (thread_group_size_x > cell_count) {
                    thread_group_size_x = cell_count
                }
                let thread_group_size = MTLSizeMake(thread_group_size_x, 1, 1)
                compute_command_encoder.dispatchThreads(grid_size, threadsPerThreadgroup: thread_group_size)
                compute_command_encoder.endEncoding()
            } else {
                let data_buffer_input_index = 1 - data_buffer_output_index
                
                let index_buffer_ptr: UnsafeMutablePointer<UInt32> = radius_index_buffer.contents().bindMemory(to: UInt32.self, capacity: Int(uniforms.inner_radius_cell_count + uniforms.outer_radius_cell_count))
                var data_out_ptr: UnsafeMutablePointer<SmoothLifeData> = data_buffer[data_buffer_output_index].contents().bindMemory(to: SmoothLifeData.self, capacity: Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d))
                let data_in_ptr: UnsafeMutablePointer<SmoothLifeData> = data_buffer[data_buffer_input_index].contents().bindMemory(to: SmoothLifeData.self, capacity: Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d))
                for i in 0..<UInt32(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d) {
                    smooth_life_cell(i, data_in_ptr, data_out_ptr, index_buffer_ptr, uniforms.board_cell_count_1d, uniforms.inner_radius_cell_count, uniforms.outer_radius_cell_count)
                }
            }
            
            self.data_buffer_output_index = 1 - self.data_buffer_output_index
        }
        
        command_buffer.commit()
        command_buffer.waitUntilCompleted()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawable_size_changed(drawable_size: size)
    }
}
