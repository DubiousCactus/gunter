const zmesh = @import("zmesh");
const gl = @import("gl");
const std = @import("std");
const zm = @import("zm");

const core = @import("core.zig");
const texture = @import("texture.zig");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const DrawOptions = struct {
    use_textures: bool = true,
    highlight: bool = false,
    highlight_shader: ?*const core.ShaderProgram = null,
};

pub fn mat4f_from_array(arr: [16]f32) zm.Mat4f {
    return zm.Mat4f{ .data = .{
        arr[0],  arr[1],  arr[2],  arr[3],
        arr[4],  arr[5],  arr[6],  arr[7],
        arr[8],  arr[9],  arr[10], arr[11],
        arr[12], arr[13], arr[14], arr[15],
    } };
}

pub const Vertex = extern struct {
    position: [3]gl.float,
    normal: [3]gl.float,
    texture_coords: [2]gl.float,
};

pub const Mesh = struct {
    indices: []gl.uint,
    vertices: []Vertex,
    textures: []texture.Texture,
    VAO: c_uint,
    VBO: c_uint,
    EBO: c_uint,
    name: [*:0]const u8 = undefined,
    world_matrix: zm.Mat4f = zm.Mat4f.identity(),
    scaling: zm.Mat4f = zm.Mat4f.identity(),

    pub fn init(
        indices: []gl.uint,
        vertices: []Vertex,
        textures: []texture.Texture,
    ) !Mesh {
        var VAO: [1]c_uint = undefined;
        var VBO: [1]c_uint = undefined;
        var EBO: [1]c_uint = undefined;
        gl.GenVertexArrays(1, &VAO);
        gl.GenBuffers(1, &VBO);
        gl.GenBuffers(1, &EBO);
        // === VAO ===
        gl.BindVertexArray(VAO[0]);
        // === VBO ===
        gl.BindBuffer(gl.ARRAY_BUFFER, VBO[0]);
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @as(isize, @intCast(@sizeOf(Vertex) * vertices.len)),
            vertices.ptr,
            gl.STATIC_DRAW,
        );
        // === EBO ===
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO[0]);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @sizeOf(gl.uint) * @as(isize, @intCast(indices.len)),
            indices.ptr,
            gl.STATIC_DRAW,
        );
        // Vertex positions
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), 0);
        // Vertex texture coordinates
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(
            1,
            2,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "texture_coords"),
        );
        // Vertex normals
        // TODO: Figure out what happens if I don't initialize normals/texture
        // coordinates for *one* mesh. Like, say I don't enable the vertex attribute
        // array for the normals. What gets passed to the shader?
        gl.EnableVertexAttribArray(2);
        gl.VertexAttribPointer(
            2,
            3,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "normal"),
        );

        gl.BindVertexArray(0); // Unbind for good measures

        return .{
            .indices = indices,
            .vertices = vertices,
            .textures = textures,
            .VAO = VAO[0],
            .VBO = VBO[0],
            .EBO = EBO[0],
        };
    }

    pub fn draw(self: Mesh, shader_program: core.ShaderProgram, options: DrawOptions) !void {
        if (options.use_textures) {
            // TODO: Move the texture parameters somewhere else!
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
            gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            // TODO: Handle more than one texture per material!
            var diffuse_nr: u8 = 1;
            var specular_nr: u8 = 1;
            // FIXME: Things start to break if the texture indices are beyond activated
            // textures. But what if I don't have the diffuse or the specular?
            var texture_mat = core.TextureMaterial{
                .diffuse_texture_index = 0,
                .specular_texture_index = 1,
                .shininess = 32.0,
            };
            for (self.textures, 0..) |tex, i| {
                // WARN: Reflect the use of mipmaps with the choice of generating mipmaps in
                // the texture loading!! This is super important or it won't render textures.
                gl.TexParameteri(
                    gl.TEXTURE_2D,
                    gl.TEXTURE_MIN_FILTER,
                    if (tex.use_mipmaps) gl.LINEAR_MIPMAP_LINEAR else gl.LINEAR,
                );
                gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(i)));
                gl.BindTexture(gl.TEXTURE_2D, tex.id);
                switch (tex.type_) {
                    .diffuse, .base_color => {
                        if (diffuse_nr > 1) {
                            std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
                            return error.TooManyTextures;
                        }
                        texture_mat.diffuse_texture_index = @as(i32, @intCast(i));
                        diffuse_nr += 1;
                    },
                    .specular, .metalic_roughness => {
                        if (specular_nr > 1) {
                            std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
                            return error.TooManyTextures;
                        }
                        texture_mat.specular_texture_index = @as(i32, @intCast(i));
                        specular_nr += 1;
                    },
                }
            }
            // TODO: Where do we store the shininess during model loading?
            try shader_program.setTextureMaterial(texture_mat);
        }
        try shader_program.setMat4f("u_model", self.world_matrix.multiply(self.scaling), false); // Do not
        // transpose because the matrix is already stored transposed in the GLTF model
        gl.BindVertexArray(self.VAO);
        gl.DrawElements(gl.TRIANGLES, @as(c_int, @intCast(self.indices.len)), gl.UNSIGNED_INT, 0);
        gl.BindVertexArray(0); // Unbind for good measures!
        gl.ActiveTexture(gl.TEXTURE0); // Reset for good measures!
    }

    pub fn set_scale(self: *Mesh, scalar: f32) void {
        self.scaling = zm.Mat4f.scaling(scalar, scalar, scalar);
    }

    pub fn scale(self: *Mesh, scalar: f32) void {
        self.scaling = self.scaling.multiply(zm.Mat4f.scaling(scalar, scalar, scalar));
    }

    pub fn deinit(self: Mesh, allocator: std.mem.Allocator) void {
        var buffers: [2]c_uint = .{ self.VBO, self.EBO };
        var vao: [1]c_uint = .{self.VAO};
        gl.DeleteBuffers(2, &buffers);
        gl.DeleteVertexArrays(1, &vao);
        for (self.textures) |text| {
            text.deinit();
        }
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

pub const Model = struct {
    meshes: std.ArrayList(Mesh),
    path: []const u8,
    directory: []const u8,
    loaded_textures: std.StringHashMap(texture.Texture),

    pub const Error = error{
        NotImplementedError,
    };

    pub const LoadingMode = enum {
        load_entire_scene,
        load_root_mesh_only,
    };

    pub fn init(path: [:0]const u8, allocator: std.mem.Allocator, mode: LoadingMode) !Model {
        std.debug.print("Loading asset: '{s}'...\n", .{path});
        zmesh.init(allocator);
        defer zmesh.deinit();
        const data = try zmesh.io.zcgltf.parseAndLoadFile(path);
        defer zmesh.io.zcgltf.freeData(data);

        var directory: []const u8 = undefined;
        if (std.fs.path.dirname(path)) |dir| {
            directory = dir;
        } else {
            log.err("failed to find the directory for {s}", .{path});
        }

        var model = Model{
            .meshes = std.ArrayList(Mesh).init(allocator),
            .directory = std.mem.sliceTo(directory, 0),
            .path = path,
            .loaded_textures = std.StringHashMap(texture.Texture).init(allocator),
        };
        switch (mode) {
            .load_entire_scene => {
                try model.load_entire_scene(data, allocator);
            },
            .load_root_mesh_only => {
                try model.load_root_mesh(data, allocator);
            },
        }
        return model;
    }

    fn load_entire_scene(self: *Model, data: *zmesh.io.zcgltf.Data, allocator: std.mem.Allocator) !void {
        var root_progress = std.Progress.start(.{});
        defer root_progress.end();
        std.debug.print("\t[*]Parsing the scene...\n", .{});
        var scene_progress = root_progress.start("Parsing the scene", 0);
        defer scene_progress.end();
        if (data.scene) |main_scene| {
            std.debug.print("Scene has {d} nodes\n", .{main_scene.nodes_count});
            if (main_scene.nodes) |nodes| {
                var nodes_progress = scene_progress.start("Loading nodes", main_scene.nodes_count);
                defer nodes_progress.end();
                for (nodes[0..main_scene.nodes_count]) |node| {
                    const root_node: *zmesh.io.zcgltf.Node = node;
                    try self.load_node(root_node, allocator, nodes_progress);
                }
            }
        } else {
            log.err("failed to find a main scene for gltf file: {s}", .{self.path});
            return error.NoMainSceneFound;
        }
    }

    fn load_root_mesh(self: *Model, data: *zmesh.io.zcgltf.Data, allocator: std.mem.Allocator) !void {
        var mesh_indices = std.ArrayList(u32).init(allocator);
        var mesh_positions = std.ArrayList([3]f32).init(allocator);
        var mesh_normals = std.ArrayList([3]f32).init(allocator);

        try zmesh.io.zcgltf.appendMeshPrimitive(
            data,
            0, // mesh index
            0, // gltf primitive index (submesh index)
            &mesh_indices,
            &mesh_positions,
            &mesh_normals, // normals (optional)
            null, // texcoords (optional)
            null, // tangents (optional)
        );

        _ = self;
        // FIXME:
        // self.meshes.append(Mesh.init(
        //     try mesh_indices.toOwnedSlice(),
        //     try mesh_positions.toOwnedSlice(),
        //     try mesh_normals.toOwnedSlice(),
        //     undefined,
        // ));
    }

    fn load_node(
        self: *Model,
        node: *zmesh.io.zcgltf.Node,
        allocator: std.mem.Allocator,
        progress_node: std.Progress.Node,
    ) !void {
        if (node.mesh) |mesh| {
            var processed_mesh = try self.process_mesh(
                mesh,
                allocator,
                progress_node,
            );
            processed_mesh.world_matrix = mat4f_from_array(node.transformWorld());
            processed_mesh.name = node.name orelse "noname";
            try self.meshes.append(processed_mesh);
            progress_node.setCompletedItems(self.meshes.items.len);
        }
        if (node.children) |children| {
            std.debug.print("Node has {d} children\n", .{node.children_count});
            progress_node.increaseEstimatedTotalItems(node.children_count);
            for (0..node.children_count) |i| {
                try self.load_node(children[i], allocator, progress_node);
            }
        }
    }

    fn process_mesh(
        self: *Model,
        mesh: *zmesh.io.zcgltf.Mesh,
        allocator: std.mem.Allocator,
        progress_node: std.Progress.Node,
    ) !Mesh {
        // TODO: Flip UVs
        // TODO: re-allocate memory to get rid of the ArrayList (make things simpler /
        // more mem efficient in the Mesh class!). Although in certain cases
        // .toOwnedSlice() may re-allocate and copy memory! That would be bad... Errr
        // let's see. At best, we should implement this choice at comptime and use a
        // flag to select a strategy.
        // TODO: Load textures and materials
        // TODO: Load model matrices, etc.
        var vertices = std.ArrayList(Vertex).init(allocator);
        var indices = std.ArrayList(gl.uint).init(allocator);
        var textures = std.ArrayList(texture.Texture).init(allocator);
        var mesh_prim_progress: std.Progress.Node = progress_node.start("Processing mesh primitive sets", mesh.primitives_count);
        defer mesh_prim_progress.end();
        std.debug.print("Mesh has {d} primitive sets\n", .{mesh.primitives_count});
        // NOTE: It seems that a mesh having just one primitive is normal, and we could
        // view this as the primitive type. So if my mesh has only 1 triangle primitive,
        // it means it only has one data buffer for "triangle", although the buffer may
        // contain many more than 3 vertices.
        // INFO: The data is usually stored in buffers and retrieved by accessors, which
        // are methods for retrieving the data as typed arrays. The number of elements
        // found in an accessor is in accessor.count.
        for (mesh.primitives[0..mesh.primitives_count], 0..mesh.primitives_count) |primitive, k| {
            var mesh_attr_progress: std.Progress.Node = mesh_prim_progress.start(
                "Processing mesh attributes",
                0,
            );
            defer mesh_attr_progress.end();
            std.debug.print("Primitive has {d} attribute types\n", .{primitive.attributes_count});
            if (primitive.indices) |idx| {
                std.debug.print("Primitive has {d} indices of type 'uint'. Loading...\n", .{idx.count});
                // INFO: When indices is set, the primitive is "indexed", meaning its
                // attributes data are accessed via an "accessor" using the attribute's
                // index. The value of 'indices' indicates the upper (exclusive) bound
                // on the index values in the 'indices' accessor, i.e., all index values
                // must be less than attribute accessors' count.
                // NOTE: Is an indexed primitive just a triangle/square?
                try indices.ensureTotalCapacity(indices.items.len + idx.count); // Pre-allocate
                // so we don't do many small allocations (bad syscalls! bad!!)
                for (0..idx.count) |i|
                    indices.appendAssumeCapacity(@as(gl.uint, @intCast(idx.readIndex(i))));
                std.debug.print("Done loading primitive indices!\n", .{});
            } else {
                // INFO: The attribute accessors' count indicates the number of vertices
                // to render.
                // WARN: BUT WHERE DO WE FIND THE VERTICES??? Oh, I guess they're
                // directly found in the attribute accessor, in order, like:
                // const num_vertices = attr.data.count;
                // for (0..num_vertices) {
                //     attr.data.unpackFloat();
                // }
                return Model.Error.NotImplementedError;
            }
            const attribute_types = primitive.attributes[0..primitive.attributes_count];
            var vertex: Vertex = Vertex{
                .position = undefined,
                .normal = undefined,
                .texture_coords = undefined,
            };
            for (attribute_types) |attr|
                std.debug.print("Attribute has {d} elements of type '{s}'. Loading...\n", .{ attr.data.count, attr.name orelse "NONE" });
            mesh_attr_progress.increaseEstimatedTotalItems(attribute_types[0].data.count);
            for (0..attribute_types[0].data.count) |i| {
                vertex = Vertex{
                    .position = undefined,
                    .normal = undefined,
                    .texture_coords = undefined,
                };
                for (attribute_types) |attr| {
                    switch (attr.type) {
                        // NOTE: In theory the type should correspond to the data type
                        // (ie vec3, vec2, etc.). But in the Zig wrapper, it matches
                        // both the name and the data type.
                        .position => {
                            _ = attr.data.readFloat(i, &vertex.position);
                        },
                        .normal => {
                            _ = attr.data.readFloat(i, &vertex.normal);
                        },
                        .tangent => {
                            // log.err("tangent attributes not implemented.", .{});
                        },
                        .texcoord => {
                            _ = attr.data.readFloat(i, &vertex.texture_coords);
                        },
                        .color => {
                            // log.err("color attributes not implemented.", .{});
                        },
                        .joints => {
                            // log.err("joints attributes not implemented.", .{});
                        },
                        .weights => {
                            // log.err("weights attributes not implemented.", .{});
                        },
                        else => {
                            log.err("can't handle this type of attribute: {s}\n", .{attr.name orelse "empty"});
                        },
                    }
                }
                try vertices.append(vertex);
                mesh_attr_progress.setCompletedItems(i);
            }

            if (primitive.material) |material| {
                var material_progress: std.Progress.Node = mesh_attr_progress.start("Processing material", 0);
                defer material_progress.end();
                if (material.has_pbr_specular_glossiness == 1) {
                    // INFO: It seems to also support PBR specular-glossiness with our
                    // familiar diffuse and specular maps! Hooray
                    std.debug.print("Material is PBRspecularGlossiness\n", .{});
                    if (material.pbr_specular_glossiness.diffuse_texture.texture) |tex| {
                        try textures.append(try self.load_texture(tex, .diffuse, allocator));
                        std.debug.print("Material diffuse color is a texture\n", .{});
                    } else {
                        std.debug.print("material diffuse color is a factor\n", .{});
                    }
                    if (material.pbr_specular_glossiness.specular_glossiness_texture.texture) |tex| {
                        try textures.append(try self.load_texture(tex, .specular, allocator));
                        std.debug.print("Material specular-glossiness is a texture\n", .{});
                    } else {
                        std.debug.print("material specular-glossiness are factors\n", .{});
                    }
                } else if (material.has_pbr_metallic_roughness == 1) {
                    // INFO: gLTF2.0 uses the PBR metallic-roughness material model. It's
                    // composed of 3 properties: 1) base color, 2) metalness, 3) roughness.
                    // Each property's value can be defined either as a) a factor between
                    // 0.0 and 1.0, or b) a texture.
                    std.debug.print("Material is PBRmetallicRoughness\n", .{});
                    if (material.pbr_metallic_roughness.base_color_texture.texture) |tex| {
                        try textures.append(try self.load_texture(tex, .base_color, allocator));
                        std.debug.print("Material base color is a texture\n", .{});
                    } else {
                        std.debug.print("material base color is a factor\n", .{});
                    }
                    if (material.pbr_metallic_roughness.metallic_roughness_texture.texture) |tex| {
                        try textures.append(try self.load_texture(tex, .metalic_roughness, allocator));
                        std.debug.print("Material metalic roughness is a texture\n", .{});
                    } else {
                        std.debug.print("material metallic rougness are factors\n", .{});
                    }
                } else {
                    log.err("Unable to load material {s}", .{material.name orelse "empty"});
                }
            }
            mesh_prim_progress.setCompletedItems(k);
        }
        std.debug.print("Initializing Mesh with {d} vertices...\n", .{vertices.items.len});
        return try Mesh.init(
            try indices.toOwnedSlice(),
            try vertices.toOwnedSlice(),
            try textures.toOwnedSlice(),
        );
    }

    fn load_texture(
        self: *Model,
        gltf_texture: *zmesh.io.zcgltf.Texture,
        texture_type: texture.TextureType,
        allocator: std.mem.Allocator,
    ) !texture.Texture {
        // INFO: A texture has an "image" source and a "sampler".
        if (gltf_texture.image == null) {
            log.err("No image provided for texture", .{});
            return texture.TextureError.NoImageProvided;
        }
        std.debug.print("Loading texture '{s}' of type {}...\n", .{ gltf_texture.image.?.name orelse "noname", texture_type });
        var texture_out: texture.Texture = undefined;
        if (gltf_texture.image.?.uri) |image_uri| {
            if (self.loaded_textures.get(std.mem.sliceTo(image_uri, 0))) |cached_texture| {
                texture_out = cached_texture;
                std.debug.print("Using cache for '{s}\n", .{image_uri});
            } else {
                texture_out = try texture.load_from_gltf_as_path(image_uri, self.directory, allocator);
                texture_out.type_ = texture_type;
                try self.loaded_textures.put(std.mem.sliceTo(image_uri, 0), texture_out);
            }
        } else if (gltf_texture.image.?.buffer_view) |buffer_view| {
            std.debug.print("Loading texture from buffer view\n", .{});
            std.debug.print("Loading {d} bytes\n", .{buffer_view.size});
            return error.NotImplementedError;
            // const image_data: ?[*]u8 = buffer_view.getData();
            // gl.BindTexture(gl.TEXTURE_2D, tbo[0]);
            // gl.TexImage2D(
            //     gl.TEXTURE_2D,
            //     0,
            //     gl.RGB,
            //     @as(c_int, @intCast(image.width)),
            //     @as(c_int, @intCast(image.height)),
            //     0,
            //     if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
            //     gl.UNSIGNED_BYTE,
            //     image_data,
            // );
            // if (generate_mipmap)
            //     gl.GenerateMipmap(gl.TEXTURE_2D);
        } else if (gltf_texture.image.?.extras.data) |image_data| {
            std.debug.print("Loading texture from data\n", .{});
            _ = image_data;
            return error.NotImplementedError;
        }
        return texture_out;
    }

    pub fn set_scale(self: *Model, scalar: f32) void {
        for (self.meshes.items) |*mesh| {
            mesh.set_scale(scalar);
        }
    }

    pub fn scale(self: *Model, scalar: f32) void {
        for (self.meshes.items) |*mesh| {
            mesh.scale(scalar);
        }
    }

    pub fn draw(
        self: *Model,
        shader_program: core.ShaderProgram,
        model_mat: zm.Mat4f,
        options: DrawOptions,
        view_mat: zm.Mat4f,
        proj_mat: zm.Mat4f,
    ) !void {
        if (options.highlight) {
            gl.Enable(gl.STENCIL_TEST);
            gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE); // Only update the stencil buffer if we pass the test.
            gl.StencilFunc(gl.ALWAYS, 1, 0xFF); // Always pass and write  1
            gl.StencilMask(0xFF); // Enable writing
        }
        try shader_program.setMat4f("u_model", model_mat, true);
        for (self.meshes.items) |mesh| {
            try mesh.draw(shader_program, options);
        }
        if (options.highlight) {
            if (options.highlight_shader == null) {
                log.err("highlight shader not provided", .{});
                return error.HighlightShaderNotProvided;
            }
            gl.StencilFunc(gl.NOTEQUAL, 1, 0xFF); // Pass test if not equal to 1
            gl.StencilMask(0x00); // Disable writing
            gl.Disable(gl.DEPTH_TEST);
            options.highlight_shader.?.use();
            try options.highlight_shader.?.setMat4f("u_view", view_mat, true);
            try options.highlight_shader.?.setMat4f("u_proj", proj_mat, true);
            try options.highlight_shader.?.setMat4f("u_model", model_mat, true);
            self.scale(1.05);
            for (self.meshes.items) |mesh| {
                try mesh.draw(options.highlight_shader.?.*, .{ .use_textures = false }); // FIXME:
                // copy other options?
            }
            gl.StencilMask(0xFF); // Enable writing
            gl.StencilFunc(gl.ALWAYS, 1, 0xFF); // Always pass and write  1
            gl.Enable(gl.DEPTH_TEST);
            shader_program.use();
            self.scale(1.0 / 1.05);
            gl.Disable(gl.STENCIL_TEST);
        }
    }

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        for (self.meshes.items) |mesh| {
            mesh.deinit(allocator);
        }
        self.meshes.deinit();
        self.loaded_textures.deinit();
    }
};

pub const Primitive = struct {
    pub fn make_cube_mesh() Mesh {
        const vertices: []gl.float = .{
            -0.5, -0.5, -0.5, 0.0, 0.0,
            0.5,  -0.5, -0.5, 1.0, 0.0,
            0.5,  0.5,  -0.5, 1.0, 1.0,
            0.5,  0.5,  -0.5, 1.0, 1.0,
            -0.5, 0.5,  -0.5, 0.0, 1.0,
            -0.5, -0.5, -0.5, 0.0, 0.0,
            -0.5, -0.5, 0.5,  0.0, 0.0,
            0.5,  -0.5, 0.5,  1.0, 0.0,
            0.5,  0.5,  0.5,  1.0, 1.0,
            0.5,  0.5,  0.5,  1.0, 1.0,
            -0.5, 0.5,  0.5,  0.0, 1.0,
            -0.5, -0.5, 0.5,  0.0, 0.0,
            -0.5, 0.5,  0.5,  1.0, 0.0,
            -0.5, 0.5,  -0.5, 1.0, 1.0,
            -0.5, -0.5, -0.5, 0.0, 1.0,
            -0.5, -0.5, -0.5, 0.0, 1.0,
            -0.5, -0.5, 0.5,  0.0, 0.0,
            -0.5, 0.5,  0.5,  1.0, 0.0,
            0.5,  0.5,  0.5,  1.0, 0.0,
            0.5,  0.5,  -0.5, 1.0, 1.0,
            0.5,  -0.5, -0.5, 0.0, 1.0,
            0.5,  -0.5, -0.5, 0.0, 1.0,
            0.5,  -0.5, 0.5,  0.0, 0.0,
            0.5,  0.5,  0.5,  1.0, 0.0,
            -0.5, -0.5, -0.5, 0.0, 1.0,
            0.5,  -0.5, -0.5, 1.0, 1.0,
            0.5,  -0.5, 0.5,  1.0, 0.0,
            0.5,  -0.5, 0.5,  1.0, 0.0,
            -0.5, -0.5, 0.5,  0.0, 0.0,
            -0.5, -0.5, -0.5, 0.0, 1.0,
            -0.5, 0.5,  -0.5, 0.0, 1.0,
            0.5,  0.5,  -0.5, 1.0, 1.0,
            0.5,  0.5,  0.5,  1.0, 0.0,
            0.5,  0.5,  0.5,  1.0, 0.0,
            -0.5, 0.5,  0.5,  0.0, 0.0,
            -0.5, 0.5,  -0.5, 0.0, 1.0,
        };
        return Mesh.init(.{}, vertices, .{});
    }
};
