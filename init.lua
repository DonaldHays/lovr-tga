local ffi = require 'ffi'

ffi.cdef [[
typedef struct { uint8_t r, g, b, a; } tga_rgba;
typedef struct { uint8_t b, g, r, a; } tga_bgra;
typedef struct { uint8_t b, g, r; } tga_bgr;
]]

-- https://paulbourke.net/dataformats/tga/

--- @type TGA
local tga = {}

local headerLength = 18

local function u16_to_rgba(src, dst, alphaBPP)
    dst.b = math.floor((bit.band(src, 0x001F) / 0x001F) * 255 + 0.5)
    dst.g = math.floor((bit.band(bit.rshift(src, 5), 0x001F) / 0x001F) * 255 + 0.5)
    dst.r = math.floor((bit.band(bit.rshift(src, 10), 0x001F) / 0x001F) * 255 + 0.5)
    if alphaBPP == 1 then
        dst.a = bit.band(src, 0x8000) ~= 0 and 255 or 0
    else
        dst.a = 255
    end
end

local function bgr_to_rgba(src, dst)
    dst.r, dst.g, dst.b, dst.a = src.r, src.g, src.b, 255
end

local function bgra_to_rgba(src, dst, alphaBPP)
    dst.r, dst.g, dst.b, dst.a = src.r, src.g, src.b, alphaBPP == 8 and src.a or 255
end

local function gray_to_rgba(src, dst)
    dst.r, dst.g, dst.b, dst.a = src, src, src, 255
end

local function gray16_to_rgba(src, dst)
    local gray = bit.band(src, 0xFF)
    local alpha = bit.band(bit.rshift(src, 8), 0xFF)
    dst.r, dst.g, dst.b, dst.a = gray, gray, gray, alpha
end

--- @param width number
--- @param height number
--- @param bottomToTop boolean
local function imgIndices(width, height, bottomToTop)
    local x, y = 0, 0

    return function()
        if y == height then
            return nil
        end

        local srcIdx = x + y * width
        local dstIdx = bottomToTop and x + (height - y - 1) * width or srcIdx

        x = x + 1
        if x == width then
            x = 0
            y = y + 1
        end

        return srcIdx, dstIdx
    end
end

--- @param src any
--- @param bpp number
--- @param width number
--- @param height number
--- @param bottomToTop boolean
local function rleIndices(src, bpp, width, height, bottomToTop)
    local srcIdx = 0
    local x, y = 0, 0

    local bytesPerPixel = math.ceil(bpp / 8)
    local runLength = 0
    local isRL = false

    return function()
        if y == height then
            return nil
        end

        if runLength == 0 then
            local run = src[srcIdx]
            isRL = bit.band(run, 0x80) ~= 0
            runLength = bit.band(run, 0x7F) + 1
            srcIdx = srcIdx + 1
        end

        runLength = runLength - 1

        local dstIdx = bottomToTop and x + (height - y - 1) * width or x + y * width
        local outSrcIdx = srcIdx

        if not isRL or runLength == 0 then
            srcIdx = srcIdx + bytesPerPixel
        end

        x = x + 1
        if x == width then
            x = 0
            y = y + 1
        end

        return outSrcIdx, dstIdx
    end
end

--- @return Blob
local function getBlob(arg)
    local blob --- @type Blob

    if type(arg) == "string" then
        blob = lovr.filesystem.newBlob(arg)
    else
        blob = arg
    end

    return blob
end

function tga.loadImage(arg)
    local blob = getBlob(arg)

    local idLength = blob:getU8(0)
    local colorMapType = blob:getU8(1)
    local imageType = blob:getU8(2)
    local colorMapFirstEntryIndex = blob:getU16(3)
    local colorMapLength = blob:getU16(5)
    local colorMapEntrySize = blob:getU8(7)
    local imageXOrigin = blob:getU16(8)
    local imageYOrigin = blob:getU16(10)
    local width = blob:getU16(12)
    local height = blob:getU16(14)
    local imageBPP = blob:getU8(16)
    local imageDesc = blob:getU8(17)

    local alphaBPP = bit.band(imageDesc, 0x0F)
    local rtl = bit.band(imageDesc, 0x10) ~= 0
    local bottomToTop = bit.band(imageDesc, 0x20) == 0
    local interleaveMode = bit.rshift(imageDesc, 6)

    if imageType == 1 then
        -- Uncompressed, color-mapped
        if colorMapType ~= 1 then
            error(string.format("unsupported color map type: %i", colorMapType))
        end

        if imageBPP ~= 8 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end
    elseif imageType == 2 then
        -- Uncompressed, RGB
        if imageBPP ~= 15 and imageBPP ~= 16 and imageBPP ~= 24 and imageBPP ~= 32 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end
    elseif imageType == 3 then
        -- Uncompressed, Grayscale
        if imageBPP ~= 8 and imageBPP ~= 16 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end

        if imageBPP == 16 and alphaBPP ~= 8 then
            error(string.format("unsupported alpha in 16-bit gray: %i", alphaBPP))
        end
    elseif imageType == 9 then
        -- RLE, color-mapped
        if imageBPP ~= 8 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end
    elseif imageType == 10 then
        -- RLE, RGB
        if imageBPP ~= 15 and imageBPP ~= 16 and imageBPP ~= 24 and imageBPP ~= 32 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end
    elseif imageType == 11 then
        -- RLE, Grayscale
        if imageBPP ~= 8 and imageBPP ~= 16 then
            error(string.format("unsupported image depth: %i", imageBPP))
        end

        if imageBPP == 16 and alphaBPP ~= 8 then
            error(string.format("unsupported alpha in 16-bit gray: %i", alphaBPP))
        end
    else
        error(string.format("unsupported image type: %i", imageType))
    end

    if rtl then
        error("no support for rtl images")
    end

    if colorMapFirstEntryIndex ~= 0 then
        error("no support for colormaps without 0 as first index")
    end

    if interleaveMode ~= 0 then
        error("no interleaving")
    end

    local colorMapStart = headerLength + idLength
    local imageDataStart = colorMapStart + (colorMapEntrySize / 8) * colorMapLength

    local img = lovr.data.newImage(width, height)
    local dst = ffi.cast("tga_rgba*", img:getPointer())

    if imageType == 1 then
        -- Uncompressed, color-mapped
        local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

        if colorMapEntrySize == 16 then
            local colorMap = ffi.cast(
                "uint16_t*",
                ffi.cast("uint8_t*", blob:getPointer()) + colorMapStart
            )

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                local colorMapIdx = src[srcIdx]
                if colorMapIdx >= colorMapLength then
                    error("color map index out of bounds")
                end
                u16_to_rgba(colorMap[colorMapIdx], dst[dstIdx], 1)
            end
        elseif colorMapEntrySize == 24 then
            local colorMap = ffi.cast(
                "tga_bgr*",
                ffi.cast("uint8_t*", blob:getPointer()) + colorMapStart
            )

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                local colorMapIdx = src[srcIdx]
                if colorMapIdx >= colorMapLength then
                    error("color map index out of bounds")
                end
                bgr_to_rgba(colorMap[colorMapIdx], dst[dstIdx])
            end
        else
            error(colorMapEntrySize)
        end
    elseif imageType == 2 then
        -- Uncompressed, RGB
        local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

        if imageBPP == 15 or imageBPP == 16 then
            src = ffi.cast("uint16_t*", src)

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                u16_to_rgba(src[srcIdx], dst[dstIdx], alphaBPP)
            end
        elseif imageBPP == 24 then
            src = ffi.cast("tga_bgr*", src)

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                bgr_to_rgba(src[srcIdx], dst[dstIdx])
            end
        elseif imageBPP == 32 then
            src = ffi.cast("tga_bgra*", src)

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                bgra_to_rgba(src[srcIdx], dst[dstIdx], 8)
            end
        else
            error("shouldn't have gotten here")
        end
    elseif imageType == 3 then
        -- Uncompressed, Grayscale

        if imageBPP == 8 then
            local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                gray_to_rgba(src[srcIdx], dst[dstIdx])
            end
        elseif imageBPP == 16 then
            local src = ffi.cast(
                "uint16_t*",
                ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart
            )

            for srcIdx, dstIdx in imgIndices(width, height, bottomToTop) do
                gray16_to_rgba(src[srcIdx], dst[dstIdx])
            end
        else
            error("shouldn't have gotten here")
        end
    elseif imageType == 9 then
        -- RLE, color-mapped
        local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

        if colorMapEntrySize == 16 then
            local colorMap = ffi.cast(
                "uint16_t*",
                ffi.cast("uint8_t*", blob:getPointer()) + colorMapStart
            )

            for srcIdx, dstIdx in rleIndices(src, imageBPP, width, height, bottomToTop) do
                local colorMapIdx = src[srcIdx]
                if colorMapIdx >= colorMapLength then
                    error("color map index out of bounds")
                end
                u16_to_rgba(colorMap[colorMapIdx], dst[dstIdx], 8)
            end
        elseif colorMapEntrySize == 32 then
            local colorMap = ffi.cast(
                "tga_bgra*",
                ffi.cast("uint8_t*", blob:getPointer()) + colorMapStart
            )

            for srcIdx, dstIdx in rleIndices(src, imageBPP, width, height, bottomToTop) do
                local colorMapIdx = src[srcIdx]
                if colorMapIdx >= colorMapLength then
                    error("color map index out of bounds")
                end
                bgra_to_rgba(colorMap[colorMapIdx], dst[dstIdx], 8)
            end
        else
            error(colorMapEntrySize)
        end
    elseif imageType == 10 then
        -- RLE, RGB
        local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

        for srcIdx, dstIdx in rleIndices(src, imageBPP, width, height, bottomToTop) do
            if imageBPP == 15 or imageBPP == 16 then
                u16_to_rgba(
                    bit.bor(src[srcIdx], bit.lshift(src[srcIdx + 1], 8)),
                    dst[dstIdx],
                    alphaBPP
                )
            else
                local out = dst[dstIdx]
                out.r = src[srcIdx + 2]
                out.g = src[srcIdx + 1]
                out.b = src[srcIdx + 0]

                if imageBPP == 32 then
                    out.a = src[srcIdx + 3]
                elseif imageBPP == 24 then
                    out.a = 255
                else
                    error("shouldn't have gotten here")
                end
            end
        end
    elseif imageType == 11 then
        -- RLE, Grayscale
        local src = ffi.cast("uint8_t*", blob:getPointer()) + imageDataStart

        if imageBPP == 8 then
            for srcIdx, dstIdx in rleIndices(src, imageBPP, width, height, bottomToTop) do
                gray_to_rgba(src[srcIdx], dst[dstIdx])
            end
        elseif imageBPP == 16 then
            for srcIdx, dstIdx in rleIndices(src, imageBPP, width, height, bottomToTop) do
                gray16_to_rgba(
                    bit.bor(src[srcIdx], bit.lshift(src[srcIdx + 1], 8)),
                    dst[dstIdx]
                )
            end
        else
            error("shouldn't have gotten here")
        end
    else
        error("shouldn't have gotten here")
    end

    return img
end

function tga.loadTexture(arg, options)
    local image = tga.loadImage(arg)
    return lovr.graphics.newTexture(image, options)
end

return tga
