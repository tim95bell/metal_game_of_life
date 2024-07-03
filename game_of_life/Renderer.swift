
import Metal
import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    
    var uniforms: Uniforms
    var device: MTLDevice
    var command_queue: MTLCommandQueue
    var library: MTLLibrary
    var vertex_function: MTLFunction
    var fragment_function: MTLFunction
    var game_of_life_function: MTLFunction
    var render_pipeline_state: MTLRenderPipelineState?
    var compute_pipeline_state: MTLComputePipelineState?
    var uniforms_buffer: MTLBuffer
    var vertex_buffer: MTLBuffer
    var use_buffer_a: Bool
    var buffer_a: MTLBuffer
    var buffer_b: MTLBuffer
    var camera_position: simd_float3
    let near_plane: Float
    let far_plane: Float
    let fov: Float
    
    static func perspective(fov: Float, aspect_ratio: Float, near_plane: Float, far_plane: Float) -> simd_float4x4 {
        let tan_half_fov = tan(fov / 2.0);

        var matrix = simd_float4x4(0.0);
        matrix[0][0] = 1.0 / (aspect_ratio * tan_half_fov);
        matrix[1][1] = 1.0 / (tan_half_fov);
        matrix[2][2] = far_plane / (far_plane - near_plane);
        matrix[2][3] = 1.0;
        matrix[3][2] = -(far_plane * near_plane) / (far_plane - near_plane);
        
        return matrix;
    }
    
    func drawable_size_changed(drawable_size: CGSize) {
        uniforms.projection_matrix = Renderer.calculate_projection_view_matrix(drawable_size: drawable_size, camera_position: camera_position, near_plane: near_plane, far_plane: far_plane, board_cell_count_1d: uniforms.board_cell_count_1d)
        uniforms_buffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout.stride(ofValue: uniforms))
    }
    
    static func calculate_projection_view_matrix(drawable_size: CGSize, camera_position: simd_float3, near_plane: Float, far_plane: Float, board_cell_count_1d: UInt32) -> simd_float4x4 {
        let fov: Float = 1.0/4.0
        let aspect_ratio: Float = Float(drawable_size.width / drawable_size.height)
        let projection_matrix = Renderer.perspective(fov: fov, aspect_ratio: aspect_ratio, near_plane: near_plane, far_plane: far_plane)
        let view_matrix = translate3d(-camera_position.x, -camera_position.y, -camera_position.z)
        return projection_matrix * view_matrix
    }

    init?(metalKitView: MTKView) {
        self.fov = 1.0/4.0
        
        let board_cell_count_1d: UInt32 = 1000
        self.far_plane = ((Float(board_cell_count_1d) / 2.0) / tan(fov/2.0)) * 2.0;
        self.near_plane = (1.0 / 2.0) / tan(fov/2.0);
        
        camera_position = simd_float3((Float(board_cell_count_1d) / 2.0), (Float(board_cell_count_1d) / 2.0), -(far_plane / 2.0))
        
        self.uniforms = Uniforms(board_cell_count_1d: board_cell_count_1d, projection_matrix: Renderer.calculate_projection_view_matrix(drawable_size: metalKitView.drawableSize, camera_position: camera_position, near_plane: near_plane, far_plane: far_plane, board_cell_count_1d: board_cell_count_1d))
        
        self.device = metalKitView.device!
        self.command_queue = self.device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!
        self.vertex_function = library.makeFunction(name: "vertex_function")!
        self.fragment_function = library.makeFunction(name: "fragment_function")!
        self.game_of_life_function = library.makeFunction(name: "game_of_life")!
        
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
        
        let vertices: [VertexIn] = [
            VertexIn(position: simd_float2(1.0, 0.0)),
            VertexIn(position: simd_float2(1.0, 1.0)),
            VertexIn(position: simd_float2(0.0,  0.0)),
            VertexIn(position: simd_float2(0.0,  1.0))
        ]
        self.vertex_buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout.stride(ofValue: vertices[0]), options: MTLResourceOptions.storageModeShared)!
        
        self.use_buffer_a = true
        
        let real_board_cell_count_1d = uniforms.board_cell_count_1d + 2
        var buffer_a_and_b_data: [UInt8] = [UInt8](repeating: 0, count: Int(real_board_cell_count_1d * real_board_cell_count_1d));
        for c in 0..<uniforms.board_cell_count_1d {
            for r in 0..<uniforms.board_cell_count_1d {
                let index = (r + 1) * real_board_cell_count_1d + c + 1
                buffer_a_and_b_data[Int(index)] = (r % 2 == 1) ? (c % 2 == 1 ? 1 : 0) : (c % 2 == 1 ? 0 : 1)
            }
        }
        self.buffer_a = device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!
        self.buffer_b = device.makeBuffer(bytes: buffer_a_and_b_data, length: buffer_a_and_b_data.count * MemoryLayout.stride(ofValue: buffer_a_and_b_data[0]), options: MTLResourceOptions.storageModeShared)!
        
        do {
            self.compute_pipeline_state = try device.makeComputePipelineState(function: game_of_life_function)
        } catch {
            print("Failed to create compute pipeline state")
        }
    
        super.init()
    }

    func draw(in view: MTKView) {
        let command_buffer = self.command_queue.makeCommandBuffer()!
        
        let compute_command_encoder = command_buffer.makeComputeCommandEncoder()!
        compute_command_encoder.setComputePipelineState(compute_pipeline_state!)
        compute_command_encoder.setBuffer(uniforms_buffer, offset: 0, index: GameOfLifeBufferIndex.uniforms.rawValue)
        compute_command_encoder.setBuffer(buffer_a, offset: 0, index: self.use_buffer_a ? GameOfLifeBufferIndex.dataOut.rawValue : GameOfLifeBufferIndex.dataIn.rawValue)
        compute_command_encoder.setBuffer(buffer_b, offset: 0, index: self.use_buffer_a ? GameOfLifeBufferIndex.dataIn.rawValue : GameOfLifeBufferIndex.dataOut.rawValue)
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
        render_encoder.setVertexBuffer(vertex_buffer, offset: 0, index: VertexBufferIndex.vertices.rawValue)
        render_encoder.setVertexBuffer(uniforms_buffer, offset: 0, index: VertexBufferIndex.uniforms.rawValue)
        render_encoder.setVertexBuffer(use_buffer_a ? buffer_a : buffer_b, offset: 0, index: VertexBufferIndex.data.rawValue)
        render_encoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: Int(uniforms.board_cell_count_1d * uniforms.board_cell_count_1d))
        render_encoder.endEncoding()
        
        let drawable = view.currentDrawable!
        command_buffer.present(drawable)
        
        command_buffer.commit()
        command_buffer.waitUntilCompleted()
        
        self.use_buffer_a = !self.use_buffer_a
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawable_size_changed(drawable_size: size)
    }
}
