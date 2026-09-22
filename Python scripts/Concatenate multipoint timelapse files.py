import sys
import subprocess

# =========================
# Auto-install dependencies
# =========================
def install_and_import(package, import_name=None):
    if import_name is None:
        import_name = package
    try:
        __import__(import_name)
    except ImportError:
        print(f"Installing {package}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        __import__(import_name)

required_packages = [
    ("numpy", "numpy"),
    ("tifffile", "tifffile"),
    ("nd2", "nd2"),
    ("imagecodecs", "imagecodecs"),
    ("scipy", "scipy"),
]

for pkg, imp in required_packages:
    install_and_import(pkg, imp)

# =========================
# Imports
# =========================
import os
import re
import numpy as np
import tifffile
from tkinter import Tk, filedialog
import nd2
from scipy.ndimage import median_filter


def ask_folder():
    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    folder = filedialog.askdirectory(title="Select folder containing .nd2 or .tif files")
    root.destroy()
    return folder


def natural_sort_key(s):
    return [int(text) if text.isdigit() else text.lower()
            for text in re.split(r"(\d+)", os.path.basename(s))]


def get_file_list(folder):
    nd2_files = sorted(
        [os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith(".nd2")],
        key=natural_sort_key
    )
    tif_files = sorted(
        [os.path.join(folder, f) for f in os.listdir(folder)
         if f.lower().endswith(".tif") or f.lower().endswith(".tiff")],
        key=natural_sort_key
    )

    if nd2_files and tif_files:
        raise ValueError("Folder contains both ND2 and TIFF files. Keep only one file type.")

    if nd2_files:
        return nd2_files, "nd2"
    if tif_files:
        return tif_files, "tif"

    raise ValueError("No .nd2 or .tif files found.")


def normalize_axes_to_ptczyx(data, axes):
    axes = axes.upper()
    axis_alias = {"S": "P", "M": "P", "V": "P"}
    axes = "".join(axis_alias.get(a, a) for a in axes)

    target_axes = "PTCZYX"
    current = {ax: i for i, ax in enumerate(axes)}

    arr = data
    for ax in target_axes:
        if ax not in current:
            arr = np.expand_dims(arr, axis=-1)
            current[ax] = arr.ndim - 1

    perm = [current[ax] for ax in target_axes]
    arr = np.transpose(arr, perm)
    return arr


def pad_to_shape(arr, target_shape):
    """
    Pad array with zeros at the end of each dimension to match target_shape.
    """
    pad_width = []
    for cur, tgt in zip(arr.shape, target_shape):
        if cur > tgt:
            raise ValueError(f"Frame shape {arr.shape} is larger than target shape {target_shape}")
        pad_width.append((0, tgt - cur))
    return np.pad(arr, pad_width, mode="constant", constant_values=0)


def read_nd2(path):
    """
    Robust ND2 reader that avoids f.asarray() when metadata is imperfect.
    Reads frames one-by-one and rebuilds the stack manually.
    """
    with nd2.ND2File(path) as f:
        full_axes = "".join(f.sizes.keys())
        full_sizes = dict(f.sizes)

        # First try normal route
        try:
            data = f.asarray()
            return normalize_axes_to_ptczyx(data, full_axes)
        except Exception as e:
            print(f"Standard ND2 read failed for {os.path.basename(path)}")
            print(f"Falling back to manual frame reconstruction...")
            print(f"Reason: {e}")

        # Manual fallback
        # Read first frame to infer per-frame dimensionality
        first_frame = np.asarray(f.read_frame(0))
        frame_ndim = first_frame.ndim

        # Infer which axes belong to sequence vs per-frame
        # Example:
        # full_axes = "PTCZYX"
        # first_frame.ndim = 2  -> frame_axes = "YX", seq_axes = "PTCZ"
        # first_frame.ndim = 3  -> frame_axes = "ZYX" or "CYX", depending on file
        frame_axes = full_axes[-frame_ndim:]
        seq_axes = full_axes[:-frame_ndim]

        # Expected number of sequence frames
        expected_n_frames = 1
        for ax in seq_axes:
            expected_n_frames *= full_sizes[ax]

        frames = []
        max_shape = list(first_frame.shape)

        # Read all frames one-by-one
        for i in range(expected_n_frames):
            fr = np.asarray(f.read_frame(i))

            # Make ndim consistent
            while fr.ndim < frame_ndim:
                fr = np.expand_dims(fr, axis=0)

            if fr.ndim != frame_ndim:
                raise ValueError(
                    f"Frame {i} in {os.path.basename(path)} has ndim={fr.ndim}, "
                    f"expected {frame_ndim}"
                )

            max_shape = [max(a, b) for a, b in zip(max_shape, fr.shape)]
            frames.append(fr)

        # Pad frames if any slight shape mismatch occurs
        fixed_frames = []
        for i, fr in enumerate(frames):
            if fr.shape != tuple(max_shape):
                print(f"Padding frame {i}: {fr.shape} -> {tuple(max_shape)}")
                fr = pad_to_shape(fr, tuple(max_shape))
            fixed_frames.append(fr)

        stacked = np.stack(fixed_frames, axis=0)

        # Rebuild full shape
        seq_shape = [full_sizes[ax] for ax in seq_axes]
        final_shape = seq_shape + list(max_shape)
        final_axes = seq_axes + frame_axes

        data = stacked.reshape(final_shape)
        return normalize_axes_to_ptczyx(data, final_axes)


def read_tif(path):
    with tifffile.TiffFile(path) as tif:
        series = tif.series[0]
        data = series.asarray()
        axes = series.axes
    return normalize_axes_to_ptczyx(data, axes)


def export_clock_embryo_projection(concat_tzcyx, output_folder, multipoint_idx):
    """
    From TZCYX data:
      1) select channel 1 (1-based -> index 0)
      2) apply FIJI-like Despeckle (3x3 median) on each Z/T plane
      3) max intensity projection along Z
      4) save as Clock_Embryo_*.tif
    """
    if concat_tzcyx.shape[2] < 1:
        raise ValueError(f"Multipoint {multipoint_idx:03d} has no channels.")

    channel_1 = concat_tzcyx[:, :, 0, :, :]  # T, Z, Y, X
    despeckled = median_filter(channel_1, size=(1, 1, 3, 3), mode="nearest")
    max_z_proj = np.max(despeckled, axis=1)  # T, Y, X

    cyan_lut = np.zeros((3, 256), dtype=np.uint8)
    cyan_lut[1, :] = np.arange(256, dtype=np.uint8)
    cyan_lut[2, :] = np.arange(256, dtype=np.uint8)

    clock_out = os.path.join(output_folder, f"Clock_Embryo_{multipoint_idx:03d}.tif")
    tifffile.imwrite(
        clock_out,
        max_z_proj,
        imagej=True,
        metadata={"axes": "TYX", "mode": "grayscale", "LUTs": [cyan_lut]},
    )
    print(f"Saved {os.path.basename(clock_out)} with cyan LUT")


def main():
    folder = ask_folder()
    if not folder:
        print("No folder selected.")
        return

    files, filetype = get_file_list(folder)

    output_folder = os.path.join(folder, "Concatenated_OME_TIFFs")
    os.makedirs(output_folder, exist_ok=True)

    first = read_nd2(files[0]) if filetype == "nd2" else read_tif(files[0])
    n_positions = first.shape[0]

    for p in range(n_positions):
        print(f"Processing multipoint {p+1}/{n_positions}")
        chunks = []

        reference_shape = None

        for fpath in files:
            arr = read_nd2(fpath) if filetype == "nd2" else read_tif(fpath)

            if p >= arr.shape[0]:
                raise ValueError(
                    f"{os.path.basename(fpath)} has only {arr.shape[0]} positions, "
                    f"but position {p+1} was requested."
                )

            current = arr[p]   # T, C, Z, Y, X

            if reference_shape is None:
                reference_shape = current.shape[1:]   # C, Z, Y, X
            else:
                if current.shape[1:] != reference_shape:
                    raise ValueError(
                        f"Shape mismatch after reading {os.path.basename(fpath)} at multipoint {p+1}:\n"
                        f"Expected per-time shape {reference_shape}, got {current.shape[1:]}"
                    )

            chunks.append(current)

        concat = np.concatenate(chunks, axis=0)   # T, C, Z, Y, X

        # Reorder to T, Z, C, Y, X for FIJI/ImageJ hyperstack compatibility
        concat_for_fiji = np.transpose(concat, (0, 2, 1, 3, 4))

        out_path = os.path.join(output_folder, f"multipoint_{p+1:03d}.tif")

        tifffile.imwrite(
            out_path,
            concat_for_fiji,
            imagej=True,
            metadata={"axes": "TZCYX"}
        )
        export_clock_embryo_projection(concat_for_fiji, output_folder, p + 1)

    print("Done!")


if __name__ == "__main__":
    main()
