const zmesh = @import("zmesh");
const gl = @import("gl");
const std = @import("std");
const zm = @import("zm");

const core = @import("core.zig");
const texture = @import("texture.zig");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const DrawOptions = struct {
    draw: bool = true,
    use_textures: bool = true,
    sort_all_meshes: bool = false,
    highlight: bool = false,
    highlight_shader: ?*const core.ShaderProgram = null,
    enable_face_culling: bool = false,
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
    name: []const u8 = undefined,
    model_matrix: zm.Mat4f = zm.Mat4f.identity(),
    // scaling: zm.Vec3f = zm.vec.Vec3f.one(),
    // translation: zm.Vec3f = zm.vec.zero(3, f32),
    // rotation: zm.Quaternionf = zm.quaternion.QuaternionBase(f32).identity(),
    draw_options: DrawOptions = .{},

    pub fn init(
        indices: []gl.uint,
        vertices: []Vertex,
        textures: []texture.Texture,
    ) Mesh {
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

    pub fn draw(
        self: Mesh,
        shader_program: core.ShaderProgram,
        global_options: DrawOptions,
        world_matrix: ?zm.Mat4f,
    ) !void {
        if (!self.draw_options.draw) {
            return;
        }
        if (global_options.use_textures and self.textures.len > 0) {
            // TODO: Handle more than one texture per material!
            var diffuse_nr: u8 = 1;
            var specular_nr: u8 = 1;
            // FIXME: Things start to break if the texture indices are beyond activated
            // textures. But what if I don't have the diffuse or the specular?
            var texture_mat = core.TextureMaterial{
                .diffuse_texture_index = undefined,
                .specular_texture_index = undefined,
                .shininess = 32.0,
            };
            for (self.textures, 0..) |tex, i| {
                // gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(i)));
                // gl.BindTexture(gl.TEXTURE_2D, tex.id);
                tex.bind(@as(c_uint, @intCast(i)));
                switch (tex.type_) {
                    .diffuse, .base_color => {
                        if (diffuse_nr > 1) {
                            std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
                            return error.TooManyTextures;
                        }
                        try shader_program.setBool("u_has_diffuse_texture", true);
                        texture_mat.diffuse_texture_index = @as(i32, @intCast(i));
                        diffuse_nr += 1;
                    },
                    .specular, .metalic_roughness => {
                        if (specular_nr > 1) {
                            std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
                            return error.TooManyTextures;
                        }
                        try shader_program.setBool("u_has_specular_texture", true);
                        texture_mat.specular_texture_index = @as(i32, @intCast(i));
                        specular_nr += 1;
                    },
                    else => {},
                }
            }
            // TODO: Where do we store the shininess during model loading?
            try shader_program.setTextureMaterial(texture_mat);
        }
        var model_matrix: zm.Mat4f = self.model_matrix;
        if (world_matrix) |val| {
            model_matrix = val.multiply(self.model_matrix);
        }
        // Transpose for OpenGL which is column-major!
        shader_program.setMat4f("u_model", model_matrix, true) catch {
            gl_log.err("Can't set u_model in current shader program!\n", .{});
        };
        if (global_options.enable_face_culling or self.draw_options.enable_face_culling) {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
        }
        gl.BindVertexArray(self.VAO);
        gl.DrawElements(gl.TRIANGLES, @as(c_int, @intCast(self.indices.len)), gl.UNSIGNED_INT, 0);
        gl.BindVertexArray(0); // Unbind for good measures!
        gl.ActiveTexture(gl.TEXTURE0); // Reset for good measures!
        gl.Disable(gl.CULL_FACE);
    }

    pub fn scale(self: *Mesh, scalar: f32) void {
        self.model_matrix = self.model_matrix.multiply(zm.Mat4f.scaling(scalar, scalar, scalar));
    }

    pub fn translate(self: *Mesh, translation: zm.Vec3f) void {
        self.model_matrix = zm.Mat4f.translationVec3(translation).multiply(self.model_matrix);
    }

    pub fn rotate(self: *Mesh, rotation: zm.Quaternionf) void {
        self.model_matrix = zm.Mat4f.fromQuaternion(rotation).multiply(self.model_matrix);
    }

    pub fn setModelMatrix(self: *Mesh, matrix: zm.Mat4f) void {
        self.model_matrix = matrix;
    }

    pub fn setDrawOptions(self: *Mesh, draw_options: DrawOptions) void {
        self.draw_options = draw_options;
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
        allocator.free(self.name);
    }
};

pub const MultiAsset = struct {
    meshes: std.ArrayList(Mesh),
    path: ?[]const u8,
    directory: ?[]const u8,
    loaded_textures: ?std.StringHashMap(texture.Texture),
    root_progress_node: ?*std.Progress.Node,
    root_name: []const u8,

    _world_matrix: zm.Mat4f = zm.Mat4f.identity(),
    scaling: zm.Mat4f = zm.Mat4f.identity(),
    rotation: zm.Mat4f = zm.Mat4f.identity(),
    translation: zm.Mat4f = zm.Mat4f.identity(),

    pub const Error = error{
        NotImplementedError,
        AssetNotFound,
    };

    pub const LoadingMode = enum {
        load_entire_scene,
        load_root_mesh_only,
    };

    pub fn initFromPath(
        path: [:0]const u8,
        allocator: std.mem.Allocator,
        context: *core.Context,
        mode: LoadingMode,
        root_name: []const u8,
    ) !MultiAsset {
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

        var multi_asset = MultiAsset{
            .meshes = std.ArrayList(Mesh).init(allocator),
            .directory = std.mem.sliceTo(directory, 0),
            .path = path,
            .loaded_textures = std.StringHashMap(texture.Texture).init(allocator),
            .root_progress_node = &context.progress_node,
            .root_name = root_name,
        };
        switch (mode) {
            .load_entire_scene => {
                try multi_asset.loadEntireScene(data, allocator);
            },
            .load_root_mesh_only => {
                try multi_asset.loadRootMesh(data, allocator);
            },
        }
        // The loaded textures are no longer needed, they were all copied to the
        // GPU! We do not want to deinit the values though, because they are the texture
        // objects used by the meshes!
        multi_asset.loaded_textures.?.clearAndFree();
        multi_asset.loaded_textures.?.deinit();
        return multi_asset;
    }

    pub fn initFromMesh(
        mesh: Mesh,
        allocator: std.mem.Allocator,
        root_name: []const u8,
    ) !MultiAsset {
        var multi_asset = MultiAsset{
            .meshes = std.ArrayList(Mesh).init(allocator),
            .directory = undefined,
            .path = undefined,
            .loaded_textures = undefined,
            .root_progress_node = undefined,
            .root_name = root_name,
        };
        try multi_asset.meshes.append(mesh);
        return multi_asset;
    }

    fn loadEntireScene(self: *MultiAsset, data: *zmesh.io.zcgltf.Data, allocator: std.mem.Allocator) !void {
        std.debug.print("\t[*]Parsing the scene...\n", .{});
        var scene_progress = self.root_progress_node.?.start("Parsing the scene", 0);
        defer scene_progress.end();
        if (data.scene) |main_scene| {
            std.debug.print("Scene has {d} nodes\n", .{main_scene.nodes_count});
            if (main_scene.nodes) |nodes| {
                var nodes_progress = scene_progress.start("Loading nodes", main_scene.nodes_count);
                defer nodes_progress.end();
                for (nodes[0..main_scene.nodes_count]) |node| {
                    const root_node: *zmesh.io.zcgltf.Node = node;
                    try self.loadNode(root_node, allocator, nodes_progress);
                }
            }
        } else {
            log.err("failed to find a main scene for gltf file: {s}", .{self.path.?});
            return error.NoMainSceneFound;
        }
    }

    fn loadRootMesh(self: *MultiAsset, data: *zmesh.io.zcgltf.Data, allocator: std.mem.Allocator) !void {
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

    fn loadNode(
        self: *MultiAsset,
        node: *zmesh.io.zcgltf.Node,
        allocator: std.mem.Allocator,
        progress_node: std.Progress.Node,
    ) !void {
        if (node.mesh) |mesh| {
            var processed_mesh = try self.processMesh(
                mesh,
                allocator,
                progress_node,
            );
            processed_mesh.model_matrix = mat4f_from_array(node.transformWorld()).transpose(); // OpenGL is column major, and so are gLTF assets
            const node_name: []const u8 = std.mem.span(node.name orelse "noname");
            processed_mesh.name = try allocator.allocSentinel(u8, node_name.len, 0);
            std.mem.copyForwards(u8, @constCast(processed_mesh.name), node_name);
            std.debug.print("Loaded mesh '{s}'\n", .{processed_mesh.name});
            try self.meshes.append(processed_mesh);
            progress_node.setCompletedItems(self.meshes.items.len);
        }
        if (node.children) |children| {
            std.debug.print("Node has {d} children\n", .{node.children_count});
            progress_node.increaseEstimatedTotalItems(node.children_count);
            for (0..node.children_count) |i| {
                try self.loadNode(children[i], allocator, progress_node);
            }
        }
    }

    fn processMesh(
        self: *MultiAsset,
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
                return MultiAsset.Error.NotImplementedError;
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
                        try textures.append(try self.loadTexture(tex, .diffuse, allocator));
                        std.debug.print("Material diffuse color is a texture\n", .{});
                    } else {
                        std.debug.print("material diffuse color is a factor\n", .{});
                        std.debug.print("FACTORS NOT IMPLEMENTED!!!!\n", .{});
                        // TODO: Load and store!
                    }
                    if (material.pbr_specular_glossiness.specular_glossiness_texture.texture) |tex| {
                        try textures.append(try self.loadTexture(tex, .specular, allocator));
                        std.debug.print("Material specular-glossiness is a texture\n", .{});
                    } else {
                        std.debug.print("material specular-glossiness are factors\n", .{});
                        std.debug.print("FACTORS NOT IMPLEMENTED!!!!\n", .{});
                        // TODO: Load and store!
                    }
                } else if (material.has_pbr_metallic_roughness == 1) {
                    // INFO: gLTF2.0 uses the PBR metallic-roughness material model. It's
                    // composed of 3 properties: 1) base color, 2) metalness, 3) roughness.
                    // Each property's value can be defined either as a) a factor between
                    // 0.0 and 1.0, or b) a texture.
                    std.debug.print("Material is PBRmetallicRoughness\n", .{});
                    if (material.pbr_metallic_roughness.base_color_texture.texture) |tex| {
                        try textures.append(try self.loadTexture(tex, .base_color, allocator));
                        std.debug.print("Material base color is a texture\n", .{});
                    } else {
                        std.debug.print("material base color is a factor\n", .{});
                        std.debug.print("FACTORS NOT IMPLEMENTED!!!!\n", .{});
                        // TODO: Load and store!
                    }
                    if (material.pbr_metallic_roughness.metallic_roughness_texture.texture) |tex| {
                        try textures.append(try self.loadTexture(tex, .metalic_roughness, allocator));
                        std.debug.print("Material metalic roughness is a texture\n", .{});
                    } else {
                        std.debug.print("material metallic rougness are factors\n", .{});
                        std.debug.print("FACTORS NOT IMPLEMENTED!!!!\n", .{});
                        // TODO: Load and store!
                    }
                } else {
                    log.err("Unable to load material {s}", .{material.name orelse "empty"});
                }
            }
            mesh_prim_progress.setCompletedItems(k);
        }
        std.debug.print("Initializing Mesh with {d} vertices...\n", .{vertices.items.len});
        return Mesh.init(
            try indices.toOwnedSlice(),
            try vertices.toOwnedSlice(),
            try textures.toOwnedSlice(),
        );
    }

    fn loadTexture(
        self: *MultiAsset,
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
        var texture_obj: texture.Texture = undefined;
        errdefer texture_obj.deinit();
        if (gltf_texture.image.?.uri) |image_uri| {
            if (self.loaded_textures.?.get(std.mem.sliceTo(image_uri, 0))) |cached_texture| {
                texture_obj = cached_texture;
                std.debug.print("Using cache for '{s}\n", .{image_uri});
            } else {
                texture_obj = texture.Texture.init(texture_type, true);

                std.debug.print("Loading texture from uri: {s}\n", .{image_uri});
                const dir = std.fs.cwd().openDir(self.directory.?, .{}) catch |err| {
                    log.err("failed to open directory: {?s}", .{self.directory.?});
                    return err;
                };
                const file = dir.openFile(std.mem.sliceTo(image_uri, 0), .{}) catch |err| {
                    log.err("failed to open texture file: {?s}", .{image_uri});
                    return err;
                };
                try texture_obj.loadFromFile(
                    file,
                    false, // TODO: Figure out why NOT flipping the texture works! WTF?? Is gltf flipping the coordinates?
                    allocator,
                );

                try self.loaded_textures.?.put(std.mem.sliceTo(image_uri, 0), texture_obj);
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
        return texture_obj;
    }

    pub fn scale(self: *MultiAsset, scalar: f32) void {
        self.scaling = zm.Mat4f.scaling(scalar, scalar, scalar).multiply(self.scaling);
        self._world_matrix = self.rotation.multiply(self.translation.multiply(self.scaling));
    }

    pub fn translate(self: *MultiAsset, t: zm.Vec3f) void {
        self.translation = zm.Mat4f.translationVec3(t).multiply(self.translation);
        self._world_matrix = self.rotation.multiply(self.translation.multiply(self.scaling));
    }

    pub fn rotate(self: *MultiAsset, quaternion: zm.Quaternionf) void {
        self.rotation = zm.Mat4f.fromQuaternion(quaternion).multiply(self.rotation);
        self._world_matrix = self.rotation.multiply(self.translation.multiply(self.scaling));
    }

    pub fn findByName(self: MultiAsset, name: []const u8) !*Mesh {
        for (self.meshes.items) |*mesh| {
            if (std.mem.eql(u8, mesh.name, name)) {
                return mesh;
            }
        }
        return MultiAsset.Error.AssetNotFound;
    }

    pub fn extract(
        self: *MultiAsset,
        name: []const u8,
        with_world_mat: bool,
        allocator: std.mem.Allocator,
    ) !MultiAsset {
        for (self.meshes.items, 0..) |mesh, i| {
            if (std.mem.eql(u8, mesh.name, name)) {
                // WARN: This breaks the order of the list. For now we don't need to
                // maintain the order so it's fine, because this is O(1).
                var found_mesh: Mesh = self.meshes.swapRemove(i);
                if (with_world_mat)
                    found_mesh.model_matrix = self._world_matrix.multiply(found_mesh.model_matrix);
                return try MultiAsset.initFromMesh(found_mesh, allocator, name);
            }
        }
        return MultiAsset.Error.AssetNotFound;
    }

    pub fn draw(
        self: *MultiAsset,
        shader_program: core.ShaderProgram,
        options: DrawOptions,
        view_mat: zm.Mat4f,
        proj_mat: zm.Mat4f,
        camera_translation: zm.Vec3f,
    ) !void {
        // TODO: Refactor the Mesh struct into a SceneNode struct to clean up operations
        // such as highlighting. Basically implement a scene tree with operations on it
        // like findByName().
        if (options.highlight) {
            gl.Enable(gl.STENCIL_TEST);
            gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE); // Only update the stencil buffer if we pass the test.
            gl.StencilFunc(gl.ALWAYS, 1, 0xFF); // Always pass and write  1
            gl.StencilMask(0xFF); // Enable writing
        }
        if (options.sort_all_meshes) {
            // Useful for transparency. Since we don't have a consistent way of tagging
            // which objects are transparent when loading a whole scene, we'll sort them
            // all for now (we do now!). But in the future, we need a mechanism to improve this, or
            // to implement order independent transparency.
            return error.NotImplementedError;
            // TODO: Use MultiArrayList.sort()
        }
        for (self.meshes.items) |mesh| {
            if (mesh.draw_options.highlight) {
                gl.Enable(gl.STENCIL_TEST);
                gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE); // Only update the stencil buffer if we pass the test.
                gl.StencilFunc(gl.ALWAYS, 1, 0xFF); // Always pass and write  1
                gl.StencilMask(0xFF); // Enable writing
            }
            // TODO: Move these out of the draw method. Since these are userspace, they
            // hsouldn't be here. And also, it's pointless to write to the GPU for every
            // damn draw call!
            try shader_program.setBool("u_has_diffuse_texture", false);
            try shader_program.setBool("u_has_specular_texture", false);
            try shader_program.setMat4f("u_view", view_mat, true);
            try shader_program.setMat4f("u_proj", proj_mat, true);
            try shader_program.setVec3f("u_cam_pos", camera_translation);
            try mesh.draw(shader_program, options, self._world_matrix);

            if (mesh.draw_options.highlight) {
                if (mesh.draw_options.highlight_shader == null) {
                    log.err("highlight shader not provided", .{});
                    return error.HighlightShaderNotProvided;
                }
                gl.StencilFunc(gl.NOTEQUAL, 1, 0xFF); // Pass test if not equal to 1
                gl.StencilMask(0x00); // Disable writing
                gl.Disable(gl.DEPTH_TEST);
                mesh.draw_options.highlight_shader.?.use();
                try mesh.draw_options.highlight_shader.?.setMat4f("u_view", view_mat, true);
                try mesh.draw_options.highlight_shader.?.setMat4f("u_proj", proj_mat, true);
                self.scale(1.02);
                // mesh.setScale(2);
                try mesh.draw(
                    mesh.draw_options.highlight_shader.?.*,
                    .{ .use_textures = false },
                    self._world_matrix,
                ); // FIXME: copy other options?
                gl.StencilMask(0xFF); // Enable writing
                gl.StencilFunc(gl.ALWAYS, 1, 0xFF); // Always pass and write  1
                gl.Enable(gl.DEPTH_TEST);
                shader_program.use();
                self.scale(1.0 / 1.02);
                // mesh.setScale(1.0);
                gl.Disable(gl.STENCIL_TEST);
            }
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
            self.scale(1.05);
            for (self.meshes.items) |mesh| {
                try mesh.draw(
                    options.highlight_shader.?.*,
                    .{ .use_textures = false },
                    self._world_matrix,
                ); // FIXME:
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

    pub fn deinit(self: *MultiAsset, allocator: std.mem.Allocator) void {
        for (self.meshes.items) |mesh| {
            mesh.deinit(allocator);
        }
        self.meshes.deinit();
        if (self.loaded_textures) |*textures| {
            textures.deinit();
        }
    }
};

pub const Primitive = struct {
    pub fn makeCubeMesh() Mesh {
        const vertices: []const Vertex = &.{
            // Back face
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // Bottom-left
            .{ .position = [3]gl.float{ 0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ 0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ 0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ -0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-left
            // Front face
            .{ .position = [3]gl.float{ -0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ 0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ -0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ -0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-left
            // Left face
            .{ .position = [3]gl.float{ -0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ -0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ -0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ -0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // top-right
            // Right face
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ 0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ 0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ 0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ 0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-left
            // Bottom face
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ 0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ 0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ 0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-left
            .{ .position = [3]gl.float{ -0.5, -0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ -0.5, -0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-right
            // Top face
            .{ .position = [3]gl.float{ -0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ 0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined }, // top-right
            .{ .position = [3]gl.float{ 0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined }, // bottom-right
            .{ .position = [3]gl.float{ -0.5, 0.5, -0.5 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined }, // top-left
            .{ .position = [3]gl.float{ -0.5, 0.5, 0.5 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined }, // bottom-left
        };
        const indices: []const gl.uint = &.{
            0,  1,  2,  3,  4,  5,
            6,  7,  8,  9,  10, 11,
            12, 13, 14, 15, 16, 17,
            18, 19, 20, 21, 22, 23,
            24, 25, 26, 27, 28, 29,
            30, 31, 32, 33, 34, 35,
        };
        return Mesh.init(@constCast(indices), @constCast(vertices), &.{});
    }

    pub fn makePlaneMesh() Mesh {
        const vertices: []const Vertex = &.{
            // positions   // texCoords
            .{ .position = [3]gl.float{ -1.0, 1.0, 0.0 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined },
            .{ .position = [3]gl.float{ -1.0, -1.0, 0.0 }, .texture_coords = [2]gl.float{ 0.0, 0.0 }, .normal = undefined },
            .{ .position = [3]gl.float{ 1.0, -1.0, 0.0 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined },

            .{ .position = [3]gl.float{ -1.0, 1.0, 0.0 }, .texture_coords = [2]gl.float{ 0.0, 1.0 }, .normal = undefined },
            .{ .position = [3]gl.float{ 1.0, -1.0, 0.0 }, .texture_coords = [2]gl.float{ 1.0, 0.0 }, .normal = undefined },
            .{ .position = [3]gl.float{ 1.0, 1.0, 0.0 }, .texture_coords = [2]gl.float{ 1.0, 1.0 }, .normal = undefined },
        };
        const indices: []const gl.uint = &.{
            0, 1, 2, 3, 4, 5,
        };
        return Mesh.init(@constCast(indices), @constCast(vertices), &.{});
    }
};
