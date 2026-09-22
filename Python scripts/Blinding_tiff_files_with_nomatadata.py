"""
Blind TIFF images by:
1) Asking user for input folder
2) Randomizing file order
3) Assigning unique random 6-digit filenames
4) Removing TIFF metadata
5) Saving a log CSV mapping original → new name
"""

import sys
import subprocess
from pathlib import Path
import csv
import time
import random

# ---------------------------------------------------
# Auto-install tifffile if needed
# ---------------------------------------------------
try:
    import tifffile as tiff
except ModuleNotFoundError:
    print("Installing tifffile...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "tifffile"])
    import tifffile as tiff

# ---------------------------------------------------
# Folder picker
# ---------------------------------------------------
import tkinter as tk
from tkinter import filedialog

def pick_folder(prompt):
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    folder = filedialog.askdirectory(title=prompt)
    root.destroy()

    if not folder:
        raise SystemExit("No folder selected.")

    return Path(folder)

# ---------------------------------------------------
# Generate unique 6-digit numbers
# ---------------------------------------------------
def generate_numbers(n):
    numbers = random.sample(range(100000, 999999), n)
    return [str(num) for num in numbers]

# ---------------------------------------------------
# Main
# ---------------------------------------------------
def main():

    input_dir = pick_folder("Select folder with TIFF files")

    output_dir = input_dir / "BLINDED_clean_images"
    output_dir.mkdir(exist_ok=True)

    files = [
        p for p in input_dir.iterdir()
        if p.is_file() and p.suffix.lower() in (".tif", ".tiff")
    ]

    if not files:
        raise SystemExit("No TIFF files found.")

    # Shuffle file order
    random.shuffle(files)

    # Generate random 6 digit numbers
    numbers = generate_numbers(len(files))

    ts = time.strftime("%Y%m%d_%H%M%S")
    log_path = output_dir / f"blinding_key_{ts}.csv"

    print("Input folder :", input_dir)
    print("Output folder:", output_dir)
    print("Log file     :", log_path)
    print("\nProcessing...\n")

    with open(log_path, "w", newline="", encoding="utf-8") as f:

        writer = csv.writer(f)
        writer.writerow(["original_file", "new_file"])

        for src, num in zip(files, numbers):

            new_name = f"{num}{src.suffix.lower()}"
            dst = output_dir / new_name

            # Read image pixels
            img = tiff.imread(src)

            # Write clean TIFF without metadata
            tiff.imwrite(
                dst,
                img,
                metadata=None,
                description=None,
                extratags=()
            )

            writer.writerow([src.name, new_name])

            print(f"✔ {src.name}  ->  {new_name}")

    print("\nBlinding complete!")

if __name__ == "__main__":
    main()