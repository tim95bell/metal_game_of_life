
func calculate_projection_view_matrix(drawable_size: CGSize, camera_position: simd_float3, near_plane: Float, far_plane: Float, board_cell_count_1d: UInt32) -> simd_float4x4 {
    let fov: Float = 1.0/4.0
    let aspect_ratio: Float = Float(drawable_size.width / drawable_size.height)
    let projection_matrix = perspective(fov: fov, aspect_ratio: aspect_ratio, near_plane: near_plane, far_plane: far_plane)
    let view_matrix = translate3d(-camera_position.x, -camera_position.y, -camera_position.z)
    return projection_matrix * view_matrix
}

func perspective(fov: Float, aspect_ratio: Float, near_plane: Float, far_plane: Float) -> simd_float4x4 {
    let tan_half_fov = tan(fov / 2.0);

    var matrix = simd_float4x4(0.0);
    matrix[0][0] = 1.0 / (aspect_ratio * tan_half_fov);
    matrix[1][1] = 1.0 / (tan_half_fov);
    matrix[2][2] = far_plane / (far_plane - near_plane);
    matrix[2][3] = 1.0;
    matrix[3][2] = -(far_plane * near_plane) / (far_plane - near_plane);
    
    return matrix;
}
