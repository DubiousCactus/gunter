const zmesh = @import("zmesh");
const zm = @import("zm");
const gl = @import("gl");
const std = @import("std");

const core = @import("core.zig");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const Vertex = extern struct {
    position: [3]gl.float,
    normal: [3]gl.float,
    texture_coords: [2]gl.float,
};

pub const Texture = struct {
    id: u8,
    type_: TextureType,

    pub const TextureType = enum {
        diffuse,
        specular,
    };
};

pub const Mesh = struct {
    indices: []gl.uint,
    vertices: []Vertex,
    textures: []Texture,
    VAO: c_uint,
    VBO: c_uint,
    EBO: c_uint,

    pub fn init(indices: []gl.uint, vertices: []Vertex, textures: []Texture) Mesh {
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
            @sizeOf(gl.uint) * indices.len,
            &indices,
            gl.STATIC_DRAW,
        );

        // Vertex positions
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Vertex), 0);
        // Vertex normals
        // TODO: Figure out what happens if I don't initialize normals/texture
        // coordinates for *one* mesh. Like, say I don't enable the vertex attribute
        // array for the normals. What gets passed to the shader?
        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(
            1,
            3,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "normal"),
        );
        // Vertex texture coordinates
        gl.EnableVertexAttribArray(2);
        gl.VertexAttribPointer(
            2,
            2,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf(Vertex),
            @offsetOf(Vertex, "texture_coords"),
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

    pub fn draw(self: Mesh, shader_program: core.ShaderProgram) !void {
        // TODO: Move the texture parameters somewhere else!
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        _ = shader_program;
        // TODO: Handle more than one texture per material!
        // var diffuse_nr: u8 = 1;
        // var specular_nr: u8 = 1;
        // var texture_mat = core.TextureMaterial{
        //     .diffuse_texture_index = undefined,
        //     .specular_texture_index = undefined,
        //     .shininess = 1,
        // };
        // for (self.textures, 0..) |texture, i| {
        //     gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(i)));
        //     gl.BindTexture(gl.TEXTURE_2D, texture.id);
        //     switch (texture.type_) {
        //         .diffuse => {
        //             if (diffuse_nr > 1) {
        //                 std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
        //                 return error.TooManyTextures;
        //             }
        //             texture_mat.diffuse_texture_index = texture.id;
        //             diffuse_nr += 1;
        //         },
        //         .specular => {
        //             if (specular_nr > 1) {
        //                 std.debug.print("Hey man we don't handle multiple textures per material. Only 1 diffuse and 1 specular allowed bro it's what it is.\n", .{});
        //                 return error.TooManyTextures;
        //             }
        //             texture_mat.specular_texture_index = texture.id;
        //             specular_nr += 1;
        //         },
        //     }
        // }
        // // TODO: Where do we store the shininess during model loading?
        // try shader_program.setTextureMaterial(texture_mat);
        // gl.ActiveTexture(gl.TEXTURE0); // TODO: Is this needed? Why?
        gl.BindVertexArray(self.VAO);
        gl.DrawElements(gl.TRIANGLES, @as(c_int, @intCast(self.indices.len)), gl.UNSIGNED_INT, 0);
        gl.BindVertexArray(0); // Unbind for good measures!
    }

    pub fn deinit(self: Mesh, allocator: std.mem.Allocator) void {
        var buffers: [2]c_uint = .{ self.VBO, self.EBO };
        var vao: [1]c_uint = .{self.VAO};
        gl.DeleteBuffers(2, &buffers);
        gl.DeleteVertexArrays(1, &vao);
        // TODO: Destroy all textures? Where are they held? I need to see how I'm
        // loading them first.
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

pub const Model = struct {
    meshes: std.ArrayList(Mesh),
    directory: []const u8,

    pub const Error = error{
        NotImplementedError,
    };

    pub fn init(path: [:0]const u8, allocator: std.mem.Allocator) !Model {
        std.debug.print("Loading asset: '{s}'...\n", .{path});
        zmesh.init(allocator);
        defer zmesh.deinit();
        var root_progress = std.Progress.start(.{});
        defer root_progress.end();
        const data = try zmesh.io.zcgltf.parseAndLoadFile(path);
        defer zmesh.io.zcgltf.freeData(data);

        // var mesh_indices = std.ArrayList(u32).init(allocator);
        // var mesh_positions = std.ArrayList([3]f32).init(allocator);
        // var mesh_normals = std.ArrayList([3]f32).init(allocator);
        //
        // try zmesh.io.zcgltf.appendMeshPrimitive(
        //     data,
        //     0, // mesh index
        //     0, // gltf primitive index (submesh index)
        //     &mesh_indices,
        //     &mesh_positions,
        //     &mesh_normals, // normals (optional)
        //     null, // texcoords (optional)
        //     null, // tangents (optional)
        // );
        std.debug.print("\t[*]Parsing the scene...\n", .{});
        var meshes: std.ArrayList(Mesh) = std.ArrayList(Mesh).init(allocator);
        if (data.scene) |main_scene| {
            std.debug.print("has {d} nodes\n", .{main_scene.nodes_count});
            if (main_scene.nodes) |nodes| {
                var scene_progress = root_progress.start("Parsing the scene", main_scene.nodes_count);
                for (0..main_scene.nodes_count) |i| {
                    const root_node: *zmesh.io.zcgltf.Node = nodes[i];
                    try Model.load_node(root_node, &meshes, allocator, scene_progress);
                }
                scene_progress.end();
            }
        } else {
            log.err("failed to find a main scene for gltf file: {s}", .{path});
            return error.NoMainSceneFound;
        }

        var directory: []const u8 = undefined;
        if (std.fs.path.dirname(path)) |dir| {
            directory = dir;
        } else {
            log.err("failed to find the directory for {s}", .{path});
        }
        return .{ .meshes = meshes, .directory = directory };
    }

    fn load_node(
        node: *zmesh.io.zcgltf.Node,
        meshes: *std.ArrayList(Mesh),
        allocator: std.mem.Allocator,
        progress_node: std.Progress.Node,
    ) !void {
        if (node.mesh) |mesh| {
            try meshes.append(try Model.process_mesh(mesh, allocator, progress_node));
        }
        if (node.children) |children| {
            for (0..node.children_count) |i| {
                try Model.load_node(children[i], meshes, allocator, progress_node);
            }
        }
    }

    pub fn process_mesh(
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
        var textures = std.ArrayList(Texture).init(allocator);
        var mesh_prim_progress: std.Progress.Node = progress_node.start("Processing mesh primitives", mesh.primitives_count);
        defer mesh_prim_progress.end();
        std.debug.print("Mesh has {d} primitive sets\n", .{mesh.primitives_count});
        // NOTE: It seems that a mesh having just one primitive is normal, and we could
        // view this as the primitive type. So if my mesh has only 1 triangle primitive,
        // it means it only has one data buffer for "triangle", although the buffer may
        // contain many more than 3 vertices.
        // INFO: The data is usually stored in buffers and retrieved by accessors, which
        // are methods for retrieving the data as typed arrays. The number of elements
        // found in an accessor is in accessor.count.
        for (mesh.primitives[0..mesh.primitives_count]) |primitive| {
            var mesh_attr_progress: std.Progress.Node = progress_node.start("Processing mesh attributes", primitive.attributes_count);
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
                            log.err("tangent attributes not implemented.", .{});
                        },
                        .texcoord => {
                            _ = attr.data.readFloat(i, &vertex.texture_coords);
                        },
                        .color => {
                            log.err("color attributes not implemented.", .{});
                        },
                        .joints => {
                            log.err("joints attributes not implemented.", .{});
                        },
                        .weights => {
                            log.err("weights attributes not implemented.", .{});
                        },
                        else => {
                            log.err("can't handle this type of attribute: {s}\n", .{attr.name orelse "empty"});
                        },
                    }
                }
                try vertices.append(vertex);
            }

            if (primitive.material) |material| {
                if (material.has_pbr_specular_glossiness == 1) {
                    // INFO: It seems to also support PBR specular-glossiness with our
                    // familiar diffuse and specular maps! Hooray
                    std.debug.print("Material is PBRspecularGlossiness\n", .{});
                    // material.pbr_specular_glossiness.diffuse_factor;
                    // material.pbr_specular_glossiness.diffuse_texture;
                    // material.pbr_specular_glossiness.specular_factor;
                    // material.pbr_specular_glossiness.glossiness_factor;
                    // material.pbr_specular_glossiness.specular_glossiness_texture;
                    if (material.pbr_specular_glossiness.diffuse_texture.texture) |texture| {
                        _ = texture;
                        std.debug.print("Material diffuse color is a texture\n", .{});
                    } else {
                        std.debug.print("material diffuse color is a factor\n", .{});
                    }
                    if (material.pbr_specular_glossiness.specular_glossiness_texture.texture) |texture| {
                        _ = texture;
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
                    // material.pbr_metallic_roughness.base_color_factor;
                    if (material.pbr_metallic_roughness.base_color_texture.texture) |texture| {
                        try textures.append(Model.load_texture(texture));
                        std.debug.print("Material base color is a texture\n", .{});
                    } else {
                        std.debug.print("material base color is a factor\n", .{});
                    }
                    if (material.pbr_metallic_roughness.metallic_roughness_texture.texture) |texture| {
                        _ = texture;
                        std.debug.print("Material metalic roughness is a texture\n", .{});
                    } else {
                        std.debug.print("material metallic rougness are factors\n", .{});
                    }
                } else {
                    log.err("Unable to load material {s}", .{material.name orelse "empty"});
                }
            }
        }
        std.debug.print("Initializing Mesh with {d} vertices...\n", .{vertices.items.len});
        return Mesh.init(
            try indices.toOwnedSlice(),
            try vertices.toOwnedSlice(),
            try textures.toOwnedSlice(),
        );
    }

    fn load_texture(gltf_texture: *zmesh.io.zcgltf.Texture) Texture {
        std.debug.print("Loading texture '{s}'...\n", .{gltf_texture.name orelse "noname"});
        return Texture{ .id = undefined, .type_ = undefined };
    }

    pub fn draw(self: Model, shader_program: core.ShaderProgram) !void {
        for (self.meshes.items) |mesh| {
            try mesh.draw(shader_program);
        }
    }

    pub fn deinit(self: Model, allocator: std.mem.Allocator) void {
        for (self.meshes.items) |mesh| {
            mesh.deinit(allocator);
        }
        self.meshes.deinit();
    }
};
