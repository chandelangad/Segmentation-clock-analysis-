import os
import numpy as np
from PIL import Image
import pandas as pd
import tkinter as tk
from tkinter import filedialog
from scipy.ndimage import gaussian_filter

# 1) Prompt user for folder via file explorer dialog
root = tk.Tk()
root.withdraw()
folder = filedialog.askdirectory(title="Select folder containing images")
root.destroy()

if not folder:
    raise ValueError("No folder selected.")

# Output subfolders
blur_folder = os.path.join(folder, "gaussian_blurred")
thresh_folder = os.path.join(folder, "thresholded")
os.makedirs(blur_folder, exist_ok=True)
os.makedirs(thresh_folder, exist_ok=True)

# 2) Get all image files in the folder
valid_ext = (".png", ".tif", ".tiff", ".jpg", ".jpeg", ".bmp")
image_files = sorted([f for f in os.listdir(folder) if f.lower().endswith(valid_ext)])

if not image_files:
    raise ValueError("No image files found in the folder.")


def ij_isodata2_threshold(hist):
    """
    ImageJ's IJ_IsoData (ISODATA2) method -- the 'Default' method used by
    Image > Adjust > Threshold.
    `hist` is a 256-element histogram (list or np.array of ints).
    """
    hist = list(hist)

    # Find mode (most populated bin) and second-highest bin
    mode = int(np.argmax(hist))
    max_count = hist[mode]

    max_count2 = 0
    for i in range(256):
        if hist[i] > max_count2 and i != mode:
            max_count2 = hist[i]

    # If mode count is more than 2x the second-highest, clamp it to 1.5x
    if max_count > (max_count2 * 2) and max_count2 != 0:
        hist[mode] = int(max_count2 * 1.5)

    # --- Standard IsoData (Ridler-Calvard) on the (possibly modified) histogram ---
    g = 1
    while hist[g - 1] == 0 and g < 254:
        g += 1
    if g == 254:
        return -1  # threshold not found

    while True:
        l_sum = totl = h_sum = toth = 0.0
        for i in range(g):
            l_sum += hist[i] * i
            totl += hist[i]
        for i in range(g, 256):
            h_sum += hist[i] * i
            toth += hist[i]

        if totl > 0 and toth > 0:
            l_mean = l_sum / totl
            h_mean = h_sum / toth
            if g == int(round((l_mean + h_mean) / 2.0)):
                break
        g += 1
        if g > 254:
            return -1

    return g


def fiji_default_threshold(img):
    hist, _ = np.histogram(img.flatten(), bins=256, range=(0, 256))
    return ij_isodata2_threshold(hist)


results = {}
max_h = 0

for fname in image_files:
    path = os.path.join(folder, fname)
    img_pil = Image.open(path)

    # Handle 32-bit (or any bit-depth) images properly:
    # normalize actual data range to 0-255
    img_arr = np.array(img_pil).astype(np.float64)

    img_min, img_max = img_arr.min(), img_arr.max()
    if img_max > img_min:
        img_arr = (img_arr - img_min) / (img_max - img_min) * 255.0
    else:
        img_arr = np.zeros_like(img_arr)

    img_8bit = img_arr.astype(np.uint8)
    h, w = img_8bit.shape  # (height, width)

    img_pil_8bit = Image.fromarray(img_8bit, mode="L")

    # Resize: m x n -> (m*10) x n, i.e. height *10, width unchanged
    new_h = h * 10
    resized_pil = img_pil_8bit.resize((w, new_h), resample=Image.BILINEAR)
    resized = np.array(resized_pil)
    h = new_h  # update h to reflect new height

    # Gaussian blur, sigma = 12
    blurred = gaussian_filter(resized.astype(np.float64), sigma=12)
    blurred_uint8 = np.clip(blurred, 0, 255).astype(np.uint8)

    # Save blurred image
    blur_path = os.path.join(blur_folder, fname)
    Image.fromarray(blurred_uint8).save(blur_path)

    # IJ_IsoData (Default) threshold
    thresh_val = fiji_default_threshold(blurred_uint8)
    binary = (blurred_uint8 > thresh_val).astype(np.uint8) * 255

    # Save thresholded image
    thresh_path = os.path.join(thresh_folder, fname)
    Image.fromarray(binary).save(thresh_path)

    # Compute boundary (first white pixel per row)
    bin01 = (binary == 255).astype(np.uint8)
    boundary_x = np.full(h, np.nan)
    for y in range(h):
        white_idx = np.where(bin01[y, :] == 1)[0]
        if len(white_idx) > 0:
            boundary_x[y] = white_idx[0]

    results[fname] = boundary_x
    max_h = max(max_h, h)

# Pad shorter columns with NaN so all columns align
for fname in results:
    if len(results[fname]) < max_h:
        pad = np.full(max_h - len(results[fname]), np.nan)
        results[fname] = np.concatenate([results[fname], pad])

# Build dataframe
df = pd.DataFrame(results)
df.insert(0, "row_y", np.arange(max_h))

# Save CSV named after the folder
folder_name = os.path.basename(os.path.normpath(folder))
csv_path = os.path.join(folder, f"{folder_name}.csv")
df.to_csv(csv_path, index=False)

print(f"Saved blurred images to: {blur_folder}")
print(f"Saved thresholded images to: {thresh_folder}")
print(f"Saved boundary data to: {csv_path}")