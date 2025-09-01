const std = @import("std");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");
const zmesh = @import("zmesh");
const zignal = @import("zignal");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const TextureError = error{
    NoImageProvided,
};

pub const TextureType = enum {
    color_framebuffer,
    depth_framebuffer,
    stencil_framebuffer,
    depth_stencil_framebuffer,
    diffuse,
    specular,
    base_color,
    metalic_roughness,
    cubemap,
};

pub const Texture = struct {
    id: c_uint,
    type_: TextureType,
    path: ?[]const u8,
    use_mipmaps: bool,

    pub fn init(type_: TextureType, use_mipmaps: bool) Texture {
        var tbo: [1]c_uint = undefined;
        gl.GenTextures(1, &tbo);
        std.debug.print("Generated texture buffer object with id={d}\n", .{tbo[0]});
        return .{
            .id = tbo[0],
            .path = undefined,
            .type_ = type_,
            .use_mipmaps = use_mipmaps,
        };
    }

    pub fn fill(self: Texture, width: i32, height: i32, channels: u8, data: ?[*]const u8) void {
        gl.BindTexture(gl.TEXTURE_2D, self.id);
        var internal_format: c_int = undefined;
        var pixel_format: c_int = undefined;
        var data_type: c_uint = undefined;
        switch (self.type_) {
            .depth_framebuffer => {
                internal_format = gl.DEPTH_COMPONENT;
                pixel_format = internal_format;
                data_type = gl.UNSIGNED_BYTE;
            },
            .stencil_framebuffer => {
                internal_format = gl.STENCIL_INDEX;
                pixel_format = internal_format;
                data_type = gl.UNSIGNED_BYTE;
            },
            .depth_stencil_framebuffer => {
                internal_format = gl.DEPTH24_STENCIL8;
                pixel_format = gl.DEPTH_STENCIL;
                data_type = gl.UNSIGNED_INT_24_8;
            },
            else => {
                internal_format = if (channels == 4) gl.RGBA else gl.RGB;
                pixel_format = internal_format;
                data_type = gl.UNSIGNED_BYTE;
            },
        }
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            internal_format,
            width,
            height,
            0,
            @as(c_uint, @intCast(pixel_format)),
            data_type,
            data,
        );
        if (self.use_mipmaps)
            gl.GenerateMipmap(gl.TEXTURE_2D);

        switch (self.type_) {
            .color_framebuffer, .depth_framebuffer, .stencil_framebuffer => {
                gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
                gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
            },
            else => {
                gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER);
                gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER);
                gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

                // WARN: Reflect the use of mipmaps with the choice of generating mipmaps in
                // the texture loading!! This is super important or it won't render textures.
                gl.TexParameteri(
                    gl.TEXTURE_2D,
                    gl.TEXTURE_MIN_FILTER,
                    if (self.use_mipmaps) gl.LINEAR_MIPMAP_LINEAR else gl.LINEAR,
                );
            },
        }
        gl.BindTexture(gl.TEXTURE_2D, 0);
    }

    pub fn fillCubeMap(
        self: Texture,
        data: [*]const u8,
        width: i32,
        height: i32,
        channels: u8,
        target_offset: u8,
    ) void {
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, self.id);
        gl.TexImage2D(
            gl.TEXTURE_CUBE_MAP_POSITIVE_X + @as(c_uint, @intCast(target_offset)),
            0,
            if (channels == 4) gl.RGBA else gl.RGB,
            width,
            height,
            0,
            if (channels == 4) gl.RGBA else gl.RGB,
            gl.UNSIGNED_BYTE,
            data,
        );
        if (self.use_mipmaps) { // WARN: Needed for cube maps??
            log.err("Mipmaps shouldn't be used for cubemaps!\n", .{});
            unreachable;
        }
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR); // NOTE: Make sure to not use mipmaps for the skybox!
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
        gl.BindTexture(gl.TEXTURE_2D, 0);
    }

    pub fn loadCubeMapFromFile(
        self: Texture,
        file: std.fs.File,
        flip_vertically: bool,
        allocator: std.mem.Allocator,
        target_offset: u8,
    ) !void {
        var image = try zigimg.Image.fromFile(allocator, @constCast(&file));
        errdefer image.deinit();
        defer image.deinit();
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
        const channels: u8 = if (image.pixelFormat().isRgba()) 4 else 3;
        self.fillCubeMap(
            pixel_data_ptr,
            @as(c_int, @intCast(image.width)),
            @as(c_int, @intCast(image.height)),
            channels,
            target_offset,
        );
    }

    pub fn loadFromFile(
        self: Texture,
        file: std.fs.File,
        flip_vertically: bool,
        allocator: std.mem.Allocator,
    ) !void {
        var image = try zigimg.Image.fromFile(allocator, @constCast(&file));
        errdefer image.deinit();
        defer image.deinit();
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
        const channels: u8 = if (image.pixelFormat().isRgba()) 4 else 3;
        self.fill(
            @as(c_int, @intCast(image.width)),
            @as(c_int, @intCast(image.height)),
            channels,
            pixel_data_ptr,
        );
    }

    pub fn bind(self: Texture, slot: c_uint) void {
        gl.ActiveTexture(gl.TEXTURE0 + slot);
        switch (self.type_) {
            .cubemap => gl.BindTexture(gl.TEXTURE_CUBE_MAP, self.id),
            else => gl.BindTexture(gl.TEXTURE_2D, self.id),
        }
    }

    pub fn deinit(self: Texture) void {
        var tbos: [1]c_uint = .{self.id};
        gl.DeleteTextures(1, &tbos);
    }
};
