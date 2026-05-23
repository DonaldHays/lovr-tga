# lovr-tga

This library allows you to load TGA files via filenames or blobs as LÖVR images
or textures.

## Usage

### APIs

```lua
--- Loads a TGA as an `Image` from `Blob` data.
--- @param blob Blob The `Blob` containing TGA data.
--- @return Image
function tga.loadImage(blob)
end

--- Loads a TGA as an `Image` from a file.
--- @param filename string The filename of the TGA data to load.
--- @return Image
function tga.loadImage(filename)
end

--- Loads a TGA as a `Texture` from `Blob` data.
--- @param blob Blob The `Blob` containing TGA data.
--- @param options TGATextureOptions Texture options.
--- @return Texture
function tga.loadTexture(blob, options)
end

--- Loads a TGA as a `Texture` from a file.
--- @param filename string The filename of the TGA data to load.
--- @param options TGATextureOptions Texture options.
--- @return Texture
function tga.loadTexture(filename, options)
end
```

### TGATextureOptions

`TGATextureOptions` are a subset of the options available in 
[lovr.graphics.newTexture](https://lovr.org/docs/lovr.graphics.newTexture). A
`?` on a field name indicates it is optional.

| Field | Type | Description |
| --- | --- | --- |
| `linear?` | `boolean` | Whether the `Texture` is in linear color space instead of sRGB. Linear textures should be used for non-color data, like normal maps. Default: `false` |
| `mipmaps?` | `number \| boolean` | The number of mipmap levels in the `Texture`, or a boolean. If `true`, a full mipmap chain will be created. If `false`, the `Texture` will only have a single mipmap. Default: `true` |
| `usage?` | `TextureUsage[]` | A list of `TextureUsage` indicating how the texture will be used. Default: `{ "sample" }` |
| `label?` | `string` | A label for the `Texture` that will show up in debugging tools. |