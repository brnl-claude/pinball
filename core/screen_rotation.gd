class_name ScreenRotation
extends RefCounted
## Helpers for in-game screen rotation (see the DisplaySettings autoload).
## "Logical" sizes and coordinates are what the player sees; the content is
## rotated clockwise by the rotation angle onto the real viewport.


## 0, 90, 180 or 270.
static func normalize(degrees: int) -> int:
	return posmod(int(roundf(degrees / 90.0)) * 90, 360)


## The size of the view as the player sees it: width and height swap when
## the content is turned a quarter.
static func logical_size(size: Vector2, rotation: int) -> Vector2:
	return Vector2(size.y, size.x) if normalize(rotation) % 180 == 90 else size


## Maps logical (rotated) UI coordinates onto the real viewport, for a
## CanvasLayer's transform.
static func canvas_transform(size: Vector2, rotation: int) -> Transform2D:
	match normalize(rotation):
		90:
			return Transform2D(PI / 2.0, Vector2(size.x, 0.0))
		180:
			return Transform2D(PI, size)
		270:
			return Transform2D(-PI / 2.0, Vector2(0.0, size.y))
		_:
			return Transform2D.IDENTITY


## The rotation from the DisplaySettings autoload, or 0 when it is not
## loaded (tests).
static func current(tree: SceneTree) -> int:
	var node: Node = tree.root.get_node_or_null("DisplaySettings") if tree else null
	return int(node.get("screen_rotation")) if node else 0
