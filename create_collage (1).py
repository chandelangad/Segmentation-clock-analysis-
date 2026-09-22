"""
create_collage.py
Builds an A-column x B-row image collage from 16/32-bit scientific TIFFs.

Layout: images fill column by column, top to bottom.
Empty slots (last column) are filled with zeros (black).

Dependencies: tifffile, numpy
Install with:  pip install tifffile numpy
"""

import os
import sys
import numpy as np
import tifffile
import tkinter as tk
from tkinter import filedialog

def pick_folder():
    root = tk.Tk()
    root.withdraw()          # hide the empty root window
    root.attributes('-topmost', True)
    folder = filedialog.askdirectory(title="Select the folder containing your TIFF images")
    root.destroy()
    if not folder:
        sys.exit("No folder selected. Exiting.")
    return folder

def get_image_files(folder):
    exts = ('.tif', '.tiff')
    files = sorted(
        f for f in os.listdir(folder)
        if f.lower().endswith(exts)
    )
    return files

def load_tile(path, target_shape, target_dtype):
    """Load a TIFF and normalise shape/dtype to match the first image."""
    img = tifffile.imread(path)
    if img.shape != target_shape:
        print(f"  WARNING: {os.path.basename(path)} shape {img.shape} "
              f"differs from target {target_shape}. Cropping/padding.")
        result = np.zeros(target_shape, dtype=img.dtype)
        slices = tuple(slice(0, min(img.shape[i], target_shape[i]))
                       for i in range(img.ndim))
        result[slices] = img[slices]
        img = result
    return img.astype(target_dtype)

def build_collage(folder, cols, rows, out_name):
    files = get_image_files(folder)
    n = len(files)
    if n == 0:
        sys.exit("No .tif/.tiff files found in the selected folder.")

    total_slots = cols * rows
    if n > total_slots:
        print(f"More images ({n}) than slots ({total_slots}). "
              f"Only the first {total_slots} will be used.")
        files = files[:total_slots]
        n = total_slots

    print(f"\nFound {n} image(s). Building {cols}×{rows} collage...")

    # --- Read first image to get tile shape and dtype ---
    first = tifffile.imread(os.path.join(folder, files[0]))
    tile_shape = first.shape
    tile_dtype = first.dtype
    print(f"Tile shape: {tile_shape}  |  dtype: {tile_dtype}")

    # --- Allocate blank canvas (zeros = black) ---
    if first.ndim == 2:
        canvas = np.zeros((rows * tile_shape[0], cols * tile_shape[1]),
                          dtype=tile_dtype)
    else:
        canvas = np.zeros((rows * tile_shape[0], cols * tile_shape[1],
                           tile_shape[2]), dtype=tile_dtype)

    # --- Stamp tiles column by column ---
    for col in range(cols):
        for row in range(rows):
            idx = col * rows + row
            if idx >= n:
                continue

            path = os.path.join(folder, files[idx])
            print(f"  Placing image {idx+1:>3}/{n}  →  col {col}, row {row}  "
                  f"({files[idx]})")
            tile = load_tile(path, tile_shape, tile_dtype)

            y = row * tile_shape[0]
            x = col * tile_shape[1]
            if first.ndim == 2:
                canvas[y:y+tile_shape[0], x:x+tile_shape[1]] = tile
            else:
                canvas[y:y+tile_shape[0], x:x+tile_shape[1], :] = tile

    # --- Save ---
    if not out_name.lower().endswith(('.tif', '.tiff')):
        out_name += '.tif'
    out_path = os.path.join(folder, out_name)
    tifffile.imwrite(out_path, canvas)
    print(f"\nCollage saved to: {out_path}")
    print(f"Canvas size: {canvas.shape}  |  dtype: {canvas.dtype}")
    blank = total_slots - n
    if blank:
        print(f"Black filler tiles: {blank}")

# ─── Main ───────────────────────────────────────────────────
if __name__ == "__main__":
    print("=== TIFF Collage Builder ===\n")

    folder = pick_folder()
    print(f"Selected folder: {folder}")

    try:
        cols = int(input("Number of columns (A): ").strip())
        rows = int(input("Number of rows    (B): ").strip())
    except ValueError:
        sys.exit("Columns and rows must be integers.")

    if cols < 1 or rows < 1:
        sys.exit("Columns and rows must be >= 1.")

    out_name = input("Output filename [collage.tif]: ").strip()
    if not out_name:
        out_name = "collage.tif"

    build_collage(folder, cols, rows, out_name)
