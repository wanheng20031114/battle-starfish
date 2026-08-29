#!/usr/bin/env python3
"""在临时目录重建像素 UI 素材并核对生产文件内容。"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


WORKSPACE = Path(__file__).resolve().parents[2]
TOOL_PATHS = (
    Path("curling/tools/extract_generated_ui_sheets.py"),
)
SOURCE_PATHS = (
    Path("assets/ui_pixel/source/settings_icons_atlas.png"),
    Path("assets/ui_pixel/source/ui_frames_atlas.png"),
)

RUNTIME_REFERENCES = {
    Path("assets/ui_pixel/production/large_sandstone_frame.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/fullscreen.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/window.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/music.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/speaker.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/accessibility.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/back.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/icons/settings_40/close.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/settings/section_two_rows.png"): (
        Path("scene/main_menu/main_menu_settings_panel.tscn"),
    ),
    Path("assets/ui_pixel/production/frames/button_sandstone.png"): (
        Path("curling/ui/components/sandstone_button.tscn"),
    ),
    Path("assets/ui_pixel/production/frames/button_aqua.png"): (
        Path("curling/ui/components/sandstone_button.tscn"),
    ),
    Path("assets/ui_pixel/production/settings/selector_field.png"): (
        Path("curling/ui/components/sandstone_option_button.tscn"),
    ),
}

REPRODUCED_RUNTIME_ASSETS = (
    Path("assets/ui_pixel/production/icons/settings_40/fullscreen.png"),
    Path("assets/ui_pixel/production/icons/settings_40/window.png"),
    Path("assets/ui_pixel/production/icons/settings_40/music.png"),
    Path("assets/ui_pixel/production/icons/settings_40/speaker.png"),
    Path("assets/ui_pixel/production/icons/settings_40/accessibility.png"),
    Path("assets/ui_pixel/production/icons/settings_40/back.png"),
    Path("assets/ui_pixel/production/icons/settings_40/close.png"),
    Path("assets/ui_pixel/production/frames/button_sandstone.png"),
    Path("assets/ui_pixel/production/frames/button_aqua.png"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def copy_workspace_file(relative_path: Path, temporary_workspace: Path) -> None:
    source = WORKSPACE / relative_path
    if not source.is_file():
        raise FileNotFoundError(f"缺少素材重建输入：{relative_path.as_posix()}")
    destination = temporary_workspace / relative_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def run_tool(temporary_workspace: Path, relative_path: Path) -> None:
    completed = subprocess.run(
        [sys.executable, str(temporary_workspace / relative_path)],
        cwd=temporary_workspace,
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{relative_path.name} 执行失败：\n{completed.stdout}{completed.stderr}"
        )


def main() -> None:
    reference_errors: list[str] = []
    for asset_path, reference_paths in RUNTIME_REFERENCES.items():
        if not (WORKSPACE / asset_path).is_file():
            reference_errors.append(f"缺少运行时素材 {asset_path.as_posix()}")
            continue
        resource_path = f"res://{asset_path.as_posix()}"
        for reference_path in reference_paths:
            reference_file = WORKSPACE / reference_path
            if resource_path not in reference_file.read_text(encoding="utf-8"):
                reference_errors.append(
                    f"{reference_path.as_posix()} 未引用 {resource_path}"
                )

    if reference_errors:
        raise RuntimeError("运行时素材引用不完整：\n" + "\n".join(reference_errors))

    with tempfile.TemporaryDirectory(prefix="battle-starfish-ui-verify-") as temp:
        temporary_workspace = Path(temp)
        for relative_path in (*TOOL_PATHS, *SOURCE_PATHS):
            copy_workspace_file(relative_path, temporary_workspace)

        run_tool(temporary_workspace, TOOL_PATHS[0])

        mismatches: list[str] = []
        for relative_path in REPRODUCED_RUNTIME_ASSETS:
            generated_path = temporary_workspace / relative_path
            if not generated_path.is_file():
                mismatches.append(f"未生成 {relative_path.as_posix()}")
                continue
            production_path = WORKSPACE / relative_path
            if not production_path.is_file():
                mismatches.append(f"缺少 {relative_path.as_posix()}")
                continue
            if sha256(generated_path) != sha256(production_path):
                mismatches.append(f"内容不同 {relative_path.as_posix()}")

        if mismatches:
            raise RuntimeError("素材重建不一致：\n" + "\n".join(mismatches))

        print(
            "UI_RUNTIME_ASSETS_OK "
            f"referenced={len(RUNTIME_REFERENCES)} "
            f"reproduced={len(REPRODUCED_RUNTIME_ASSETS)}"
        )


if __name__ == "__main__":
    main()
