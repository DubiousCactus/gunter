const std = @import("std");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");
const zmesh = @import("zmesh");
const zignal = @import("zignal");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const TextureType = enum {
    diffuse,
    specular,
    base_color,
    metalic_roughness,
};

pub const Texture = struct {
    id: c_uint,
    type_: TextureType,
    path: [*:0]const u8,
    use_mipmaps: bool,
};

pub const TextureError = error{
    NoImageProvided,
};

pub fn load_from_path(
    file_name: []const u8,
    gl_texture_type: c_uint,
    TBO: c_uint,
    target: c_uint,
    generate_mipmap: bool,
    flip_vertically: bool,
    allocator: std.mem.Allocator,
) !void {
    const file = std.fs.cwd().openFile(file_name, .{}) catch |err| {
        log.err("failed to open texture file: {?s}", .{file_name});
        return err;
    };
    return try load_from_file(
        file,
        gl_texture_type,
        TBO,
        target,
        generate_mipmap,

        flip_vertically,
        allocator,
    );
}

pub fn load_from_file(
    file: std.fs.File,
    gl_texture_type: c_uint,
    TBO: c_uint,
    target: c_uint,
    generate_mipmap: bool,
    flip_vertically: bool,
    allocator: std.mem.Allocator,
) !void {
    var image = try zigimg.Image.fromFile(allocator, @constCast(&file));
    errdefer image.deinit();
    defer image.deinit();
    gl.BindTexture(gl_texture_type, TBO);
    var pixel_data_ptr = image.rawBytes().ptr;
    if (flip_vertically) {
        var img = zignal.Image(zigimg.color.Rgb24).init(
            image.width,
            image.height,
            @constCast(image.pixels.rgb24),
        );
        img.flipTopBottom();
        pixel_data_ptr = img.asBytes().ptr;
    }
    gl.TexImage2D(
        target,
        0,
        gl.RGB,
        @as(c_int, @intCast(image.width)),
        @as(c_int, @intCast(image.height)),
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        gl.UNSIGNED_BYTE,
        pixel_data_ptr,
    );
    if (generate_mipmap)
        gl.GenerateMipmap(gl.TEXTURE_2D);
}

pub fn load_from_gltf_as_path(
    path: [*:0]const u8,
    root_dir: []const u8,
    allocator: std.mem.Allocator,
) !Texture {
    var tbo: [1]c_uint = undefined;
    gl.GenTextures(1, &tbo);
    std.debug.print("Generated texture buffer object with id={d}\n", .{tbo[0]});

    const use_mipmaps: bool = true;

    std.debug.print("Loading texture from uri: {s}\n", .{path});
    const dir = std.fs.cwd().openDir(root_dir, .{}) catch |err| {
        log.err("failed to open directory: {?s}", .{root_dir});
        return err;
    };
    const file = dir.openFile(std.mem.sliceTo(path, 0), .{}) catch |err| {
        log.err("failed to open texture file: {?s}", .{path});
        return err;
    };
    try load_from_file(
        file,
        gl.TEXTURE_2D,
        tbo[0],
        gl.TEXTURE_2D,
        use_mipmaps,
        true,
        allocator,
    );

    return .{
        .id = tbo[0],
        .path = path,
        .type_ = undefined,
        .use_mipmaps = use_mipmaps,
    };
}
