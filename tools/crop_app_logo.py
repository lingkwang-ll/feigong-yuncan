"""一次性脚本：从 app_logo_brand_full.png 精确裁切 P+ 云餐图标。

裁切规则：
- 仅保留绿色圆角方块 + 白 p + 橙 + + 云餐小碗
- 排除下方品牌文字、标语、虚线/残留线
- 四周留 5% 安全边距（可在 4%~6% 调整）
- 输出 1024×1024 与 512×512 正方形 PNG
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

# 图标主体像素 y 上限（碗底约在 y=600；文字/虚线从 y≈662 起）
ICON_BOTTOM_Y = 601
MARGIN_RATIO = 0.05
LARGE_SIZE = 1024
SMALL_SIZE = 512


def _sample_bg(arr: np.ndarray) -> np.ndarray:
    return arr[8, 8, :3].astype(int)


def _detect_icon_bbox(arr: np.ndarray, bg: np.ndarray) -> tuple[int, int, int, int]:
    zone = arr[:ICON_BOTTOM_Y]
    diff = np.max(np.abs(zone[:, :, :3].astype(int) - bg), axis=2)
    dark = (
        (zone[:, :, 0] < 100)
        & (zone[:, :, 1] < 100)
        & (zone[:, :, 2] < 100)
    )
    icon_mask = (diff > 12) & (zone[:, :, 3] > 200) & ~dark
    ys, xs = np.where(icon_mask)
    if ys.size == 0:
        raise RuntimeError("未能识别图标区域，请检查源图。")
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def _square_crop_box(
    x0: int, y0: int, x1: int, y1: int, margin_ratio: float
) -> tuple[int, int, int, int]:
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    side = max(cw, ch)
    margin = int(round(side * margin_ratio))
    canvas = side + 2 * margin
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    left = cx - canvas // 2
    top = cy - canvas // 2
    return left, top, left + canvas, top + canvas


def _clamp_crop(
    img: Image.Image, box: tuple[int, int, int, int], bg: tuple[int, ...]
) -> Image.Image:
    w, h = img.size
    left, top, right, bottom = box
    left = max(0, left)
    top = max(0, top)
    right = min(w, right)
    bottom = min(h, bottom)

    crop = img.crop((left, top, right, bottom))
    cw, ch = crop.size
    if cw == ch:
        return crop

    size = max(cw, ch)
    square = Image.new("RGBA", (size, size), bg)
    square.paste(crop, ((size - cw) // 2, (size - ch) // 2), crop)
    return square


def _verify_no_artifacts(img: Image.Image) -> None:
    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]
    bottom = arr[h - 8 : h, :, :]
    dark = (
        (bottom[:, :, 0] < 100)
        & (bottom[:, :, 1] < 100)
        & (bottom[:, :, 2] < 100)
        & (bottom[:, :, 3] > 200)
    )
    if dark.sum() > 0:
        raise RuntimeError(f"裁切结果底部仍有 {dark.sum()} 个深色残留像素。")


def crop_app_logos(
    src: Path,
    out_large: Path,
    out_small: Path,
    margin_ratio: float = MARGIN_RATIO,
) -> dict:
    img = Image.open(src).convert("RGBA")
    arr = np.array(img)
    bg_arr = _sample_bg(arr)
    bg = tuple(int(v) for v in bg_arr)

    x0, y0, x1, y1 = _detect_icon_bbox(arr, bg_arr)
    box = _square_crop_box(x0, y0, x1, y1, margin_ratio)
    crop = _clamp_crop(img, box, bg)

    large = crop.resize((LARGE_SIZE, LARGE_SIZE), Image.Resampling.LANCZOS)
    small = crop.resize((SMALL_SIZE, SMALL_SIZE), Image.Resampling.LANCZOS)

    _verify_no_artifacts(large)
    _verify_no_artifacts(small)

    out_large.parent.mkdir(parents=True, exist_ok=True)
    large.save(out_large, optimize=True)
    small.save(out_small, optimize=True)

    return {
        "source": str(src),
        "icon_bbox": (x0, y0, x1, y1),
        "crop_box": box,
        "crop_size": crop.size,
        "large_size": large.size,
        "small_size": small.size,
        "large_bytes": out_large.stat().st_size,
        "small_bytes": out_small.stat().st_size,
    }


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    ui = root / "assets" / "images" / "ui"
    src = ui / "app_logo_brand_full.png"
    info = crop_app_logos(
        src=src,
        out_large=ui / "app_logo_large.png",
        out_small=ui / "app_logo_small.png",
    )
    print("裁切完成:")
    for k, v in info.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
