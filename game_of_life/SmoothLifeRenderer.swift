
import Metal
import MetalKit
import simd

// MARK: functions to help with generating inner radius and outer radius indices
func add_first_case(indices: inout [Int32], a: Int32, b: Int32, real_board_cell_count_1d: Int32) {
    // -a, b
    indices.append(-a)
    // a, b
    indices.append(a)
    // b, -a
    indices.append(-a * real_board_cell_count_1d)
    // b, a
    indices.append(a * real_board_cell_count_1d)
}

func add_middle_case(indices: inout [Int32], a: Int32, b: Int32, real_board_cell_count_1d: Int32) {
    // -a, -b
    indices.append(-a + -b * real_board_cell_count_1d)
    // -a, b
    indices.append(-a + b * real_board_cell_count_1d)
    // a, -b
    indices.append(a + -b * real_board_cell_count_1d)
    // a, b
    indices.append(a + b * real_board_cell_count_1d)

    // -b, -a
    indices.append(-b + -a * real_board_cell_count_1d)
    // -b, a
    indices.append(-b + a * real_board_cell_count_1d)
    // b, -a
    indices.append(b + -a * real_board_cell_count_1d)
    // b, a
    indices.append(b + a * real_board_cell_count_1d)
}

func add_last_case(indices: inout [Int32], a: Int32, b: Int32, real_board_cell_count_1d: Int32) {
    // -a, -b
    indices.append(-a + -b * real_board_cell_count_1d)
    // -a, b
    indices.append(-a + b * real_board_cell_count_1d)
    // a, -b
    indices.append(a + -b * real_board_cell_count_1d)
    // a, b
    indices.append(a + b * real_board_cell_count_1d)
}

// MARK: SmoothLifeRenderer
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
    var use_buffer_a: Bool
    var buffer_a: MTLBuffer
    var buffer_b: MTLBuffer
    var camera_position: simd_float3
    let near_plane: Float
    let far_plane: Float
    let fov: Float
    
    func drawable_size_changed(drawable_size: CGSize) {
        uniforms.projection_matrix = calculate_projection_view_matrix(drawable_size: drawable_size, camera_position: camera_position, near_plane: near_plane, far_plane: far_plane, board_cell_count_1d: uniforms.board_cell_count_1d)
        uniforms_buffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout.stride(ofValue: uniforms))
    }

    init?(metalKitView: MTKView) {
        self.fov = 1.0/4.0
        
        let board_cell_count_1d: UInt32 = 100
        let inner_radius: UInt8 = 2
        let outer_radius: UInt8 = 6
        let real_board_cell_count_1d = board_cell_count_1d + 2 * UInt32(outer_radius)
        self.far_plane = ((Float(board_cell_count_1d) / 2.0) / tan(fov/2.0)) * 2.0;
        self.near_plane = (1.0 / 2.0) / tan(fov/2.0);
        
        camera_position = simd_float3((Float(board_cell_count_1d) / 2.0), (Float(board_cell_count_1d) / 2.0), -(far_plane / 2.0))
        
        var inner_radius_indices = [Int32]()
        var outer_radius_indices = [Int32]()

        let inner_radius_squared = inner_radius * inner_radius
        let outer_radius_squared = outer_radius * outer_radius
        outer: for a in 1..<(outer_radius + 1) {
            // first case, where b is zero
            do {
                let square_len = a * a
                if (square_len <= inner_radius_squared) {
                    add_first_case(indices: &inner_radius_indices, a: Int32(a), b: 0, real_board_cell_count_1d: Int32(real_board_cell_count_1d))
                } else {
                    // magnitude must always be <= outer_radius
                    assert(square_len <= outer_radius_squared)
                    add_first_case(indices: &outer_radius_indices, a: Int32(a), b: 0, real_board_cell_count_1d: Int32(real_board_cell_count_1d))
                }
            }

            // middle cases, where a > 0 && b > 0 && a != b
            for b in 1..<a {
                 let square_len = a * a + b * b
                 if (square_len <= inner_radius_squared) {
                     add_middle_case(indices: &inner_radius_indices, a: Int32(a), b: Int32(b), real_board_cell_count_1d: Int32(real_board_cell_count_1d))
                 } else if (square_len <= outer_radius_squared) {
                     add_middle_case(indices: &outer_radius_indices, a: Int32(a), b: Int32(b), real_board_cell_count_1d: Int32(real_board_cell_count_1d))
                 } else {
                     continue outer
                 }
            }

            // last case, where a == b
            do {
                let square_len = a * a * 2
                if (square_len <= inner_radius_squared) {
                    add_last_case(indices: &inner_radius_indices, a: Int32(a), b: Int32(a), real_board_cell_count_1d: Int32(real_board_cell_count_1d))
                } else if (square_len <= outer_radius_squared) {
                    add_last_case(indices: &outer_radius_indices, a: Int32(a), b: Int32(a), real_board_cell_count_1d: Int32(real_board_cell_count_1d))
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
        
        self.use_buffer_a = true
        
        var buffer_a_and_b_data: [SmoothLifeData] = [SmoothLifeData](repeating: 0, count: Int(real_board_cell_count_1d * real_board_cell_count_1d));
        for c in 0..<uniforms.board_cell_count_1d {
            for r in 0..<uniforms.board_cell_count_1d {
                let index = (r + UInt32(uniforms.outer_radius)) * real_board_cell_count_1d + c + UInt32(uniforms.outer_radius)
                buffer_a_and_b_data[Int(index)] = (r % 2 == 1) ? (c % 2 == 1 ? 1.0 : 0.0) : (c % 2 == 1 ? 0.0 : 1.0)
            }
        }
        self.buffer_a = device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!
        self.buffer_b = device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!
        
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
        
        let compute_command_encoder = command_buffer.makeComputeCommandEncoder()!
        compute_command_encoder.setComputePipelineState(compute_pipeline_state!)
        compute_command_encoder.setBuffer(uniforms_buffer, offset: 0, index: SmoothLifeUpdateBufferIndex.uniforms.rawValue)
        compute_command_encoder.setBuffer(buffer_a, offset: 0, index: self.use_buffer_a ? SmoothLifeUpdateBufferIndex.dataOut.rawValue : SmoothLifeUpdateBufferIndex.dataIn.rawValue)
        compute_command_encoder.setBuffer(buffer_b, offset: 0, index: self.use_buffer_a ? SmoothLifeUpdateBufferIndex.dataIn.rawValue : SmoothLifeUpdateBufferIndex.dataOut.rawValue)
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
        
        let render_pass_descriptor = view.currentRenderPassDescriptor!
        render_pass_descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
        let render_encoder = command_buffer.makeRenderCommandEncoder(descriptor: render_pass_descriptor)!
        render_encoder.setRenderPipelineState(self.render_pipeline_state!)
        render_encoder.setVertexBuffer(vertex_buffer, offset: 0, index: SmoothLifeVertexBufferIndex.vertices.rawValue)
        render_encoder.setVertexBuffer(uniforms_buffer, offset: 0, index: SmoothLifeVertexBufferIndex.uniforms.rawValue)
        render_encoder.setVertexBuffer(use_buffer_a ? buffer_a : buffer_b, offset: 0, index: SmoothLifeVertexBufferIndex.data.rawValue)
        render_encoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d))
        render_encoder.endEncoding()
        
        let drawable = view.currentDrawable!
        command_buffer.present(drawable, afterMinimumDuration: 1.0/5.0)
        
        command_buffer.commit()
        command_buffer.waitUntilCompleted()
        
        self.use_buffer_a = !self.use_buffer_a
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawable_size_changed(drawable_size: size)
    }
}
