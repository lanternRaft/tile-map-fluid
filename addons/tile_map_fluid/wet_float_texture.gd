class_name WetFloatTexture
extends RefCounted
## Stable texture identity with native packed-array copies, never per-texel script setters.

## All data textures stay below Compatibility's minimum guaranteed texture width.
const WIDTH: int = 1024

## Owned GPU resource, shared by every batch material binding.
var texture: ImageTexture = ImageTexture.new()
## Padded upload bytes, excluding the CPU simulation and mesh storage.
var byte_count: int = 0
var _size: Vector2i


## Upload float32 data without quantizing saturation or interpreting it as color.
func upload(values: PackedFloat32Array, components: int) -> void:
	var pixels: int = maxi(1, ceili(float(values.size()) / components))
	var size: Vector2i = Vector2i(mini(WIDTH, pixels), ceili(float(pixels) / WIDTH))
	var bytes: PackedByteArray = values.to_byte_array()
	byte_count = size.x * size.y * components * 4
	bytes.resize(byte_count)
	var image: Image = Image.create_from_data(size.x, size.y, false,
		Image.FORMAT_RF if components == 1 else Image.FORMAT_RGBAF, bytes)
	if _size == size:
		texture.update(image)
	else:
		texture.set_image(image)
		_size = size
