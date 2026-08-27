from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image


WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE_DIRECTORY = WORKSPACE / "assets" / "ui_pixel" / "source"
OUTPUT_DIRECTORY = WORKSPACE / "assets" / "ui_pixel" / "production"
ALPHA_THRESHOLD = 32
ICON_PADDING = 18
FRAME_PADDING = 10

SETTINGS_ICON_NAMES = (
    ("display", "window", "fullscreen", "speaker"),
    ("music", "accessibility", "reduced_motion", "confirm"),
    ("arrow_left", "arrow_right", "back", "close"),
)

FRAME_NAMES = (
    ("button_sandstone", "button_aqua", "input_aqua"),
    ("section_aqua", "icon_tile", "value_badge"),
    ("sidebar_sandstone", "title_plaque", "notice_aqua"),
)

SETTINGS_RUNTIME_ICONS = {
    "window",
    "fullscreen",
    "speaker",
    "music",
    "accessibility",
    "back",
    "close",
}

RUNTIME_FRAMES = {
    "button_sandstone",
    "button_aqua",
    "section_aqua",
}


def validate_rgba(image: Image.Image, label: str) -> None:
    if image.mode != "RGBA":
        raise RuntimeError(f"{label} must be native RGBA, got {image.mode}")
    alpha = image.getchannel("A")
    extrema = alpha.getextrema()
    if extrema[0] != 0 or extrema[1] < 240:
        raise RuntimeError(
            f"{label} must contain transparent and near-opaque pixels: {extrema}"
        )
    corners = (
        alpha.getpixel((0, 0)),
        alpha.getpixel((image.width - 1, 0)),
        alpha.getpixel((0, image.height - 1)),
        alpha.getpixel((image.width - 1, image.height - 1)),
    )
    if any(corners):
        raise RuntimeError(f"{label} corners must be transparent: {corners}")


def threshold_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    # 仅使用现有 Alpha 判断主体边界，不读取或推断 RGB 背景颜色。
    mask = image.getchannel("A").point(
        lambda alpha: 255 if alpha >= ALPHA_THRESHOLD else 0
    )
    bbox = mask.getbbox()
    if bbox is None:
        raise RuntimeError("Atlas cell contains no visible subject")
    return bbox


def expanded_bbox(
    bbox: tuple[int, int, int, int],
    image_size: tuple[int, int],
    padding: int,
) -> tuple[int, int, int, int]:
    left, top, right, bottom = bbox
    width, height = image_size
    return (
        max(0, left - padding),
        max(0, top - padding),
        min(width, right + padding),
        min(height, bottom + padding),
    )


def place_on_square(image: Image.Image) -> Image.Image:
    side = max(image.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(
        image,
        ((side - image.width) // 2, (side - image.height) // 2),
    )
    return canvas


def fit_to_canvas(image: Image.Image, canvas_size: tuple[int, int]) -> Image.Image:
    canvas_width, canvas_height = canvas_size
    scale = min(
        (canvas_width - 4) / image.width,
        (canvas_height - 4) / image.height,
    )
    resized = image.resize(
        (
            max(1, round(image.width * scale)),
            max(1, round(image.height * scale)),
        ),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        (
            (canvas_width - resized.width) // 2,
            (canvas_height - resized.height) // 2,
        ),
    )
    return canvas


def add_transparent_border(image: Image.Image, padding: int = 4) -> Image.Image:
    canvas = Image.new(
        "RGBA",
        (image.width + padding * 2, image.height + padding * 2),
        (0, 0, 0, 0),
    )
    canvas.alpha_composite(image, (padding, padding))
    return canvas


def save_validated(image: Image.Image, path: Path) -> None:
    validate_rgba(image, path.name)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def extract_icon_grid(
    source_path: Path,
    names: tuple[tuple[str, ...], ...],
    output_subdirectory: str,
    runtime_names: set[str],
) -> dict[str, object]:
    image = Image.open(source_path)
    validate_rgba(image, source_path.name)
    rows = len(names)
    columns = len(names[0])
    metadata: dict[str, object] = {}

    for row_index, row in enumerate(names):
        top = round(row_index * image.height / rows)
        bottom = round((row_index + 1) * image.height / rows)
        for column_index, name in enumerate(row):
            left = round(column_index * image.width / columns)
            right = round((column_index + 1) * image.width / columns)
            cell = image.crop((left, top, right, bottom))
            subject_bbox = threshold_bbox(cell)
            crop_bbox = expanded_bbox(subject_bbox, cell.size, ICON_PADDING)
            output = place_on_square(cell.crop(crop_bbox))
            display_output = fit_to_canvas(output, (40, 40))
            display_path = (
                OUTPUT_DIRECTORY
                / "icons"
                / f"{output_subdirectory}_40"
                / f"{name}.png"
            )
            if name in runtime_names:
                save_validated(display_output, display_path)
            if name in runtime_names:
                metadata[name] = {
                    "source_cell": (left, top, right, bottom),
                    "subject_bbox": subject_bbox,
                    "crop_bbox": crop_bbox,
                    "output_size": output.size,
                    "display_size": display_output.size,
                }
                print(f"EXTRACTED_ICON {output_subdirectory}/{name}: {output.size}")

    return metadata


def alpha_components(image: Image.Image) -> list[dict[str, object]]:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    visited = bytearray(width * height)
    components: list[dict[str, object]] = []

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if visited[index] or pixels[x, y] < ALPHA_THRESHOLD:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[index] = 1
            area = 0
            min_x = max_x = x
            min_y = max_y = y

            while queue:
                current_x, current_y = queue.popleft()
                area += 1
                min_x = min(min_x, current_x)
                max_x = max(max_x, current_x)
                min_y = min(min_y, current_y)
                max_y = max(max_y, current_y)

                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_index = next_y * width + next_x
                    if visited[next_index] or pixels[next_x, next_y] < ALPHA_THRESHOLD:
                        continue
                    visited[next_index] = 1
                    queue.append((next_x, next_y))

            if area >= 20_000:
                bbox = (min_x, min_y, max_x + 1, max_y + 1)
                components.append(
                    {
                        "area": area,
                        "bbox": bbox,
                        "center": (
                            (bbox[0] + bbox[2]) / 2.0,
                            (bbox[1] + bbox[3]) / 2.0,
                        ),
                    }
                )

    return components


def extract_frames(source_path: Path) -> dict[str, object]:
    image = Image.open(source_path)
    validate_rgba(image, source_path.name)
    components = alpha_components(image)
    if len(components) != 9:
        raise RuntimeError(f"Expected 9 UI frames, found {len(components)}")

    components.sort(key=lambda component: float(component["center"][1]))
    rows = [components[index : index + 3] for index in range(0, 9, 3)]
    for row in rows:
        row.sort(key=lambda component: float(component["center"][0]))

    metadata: dict[str, object] = {}
    for row_index, row in enumerate(rows):
        for column_index, component in enumerate(row):
            name = FRAME_NAMES[row_index][column_index]
            subject_bbox = tuple(int(value) for value in component["bbox"])
            crop_bbox = expanded_bbox(subject_bbox, image.size, FRAME_PADDING)
            output = add_transparent_border(image.crop(crop_bbox))
            if name in RUNTIME_FRAMES:
                output_path = OUTPUT_DIRECTORY / "frames" / f"{name}.png"
                save_validated(output, output_path)
            if name in RUNTIME_FRAMES:
                metadata[name] = {
                    "area": int(component["area"]),
                    "subject_bbox": subject_bbox,
                    "crop_bbox": crop_bbox,
                    "output_size": output.size,
                }
                print(f"EXTRACTED_FRAME {name}: {output.size}")

    return metadata


def main() -> None:
    settings_source = SOURCE_DIRECTORY / "settings_icons_atlas.png"
    frames_source = SOURCE_DIRECTORY / "ui_frames_atlas.png"

    metadata = {
        "alpha_threshold_for_bounds": ALPHA_THRESHOLD,
        "resampling": "none; Godot applies linear filtering at display time",
        "sources": {
            "settings_icons": settings_source.relative_to(WORKSPACE).as_posix(),
            "frames": frames_source.relative_to(WORKSPACE).as_posix(),
        },
        "settings_icons": extract_icon_grid(
            settings_source,
            SETTINGS_ICON_NAMES,
            "settings",
            SETTINGS_RUNTIME_ICONS,
        ),
        "frames": extract_frames(frames_source),
    }

    metadata_path = OUTPUT_DIRECTORY / "generated_ui_assets.json"
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"GENERATED_UI_EXTRACTION_OK {OUTPUT_DIRECTORY}")


if __name__ == "__main__":
    main()
