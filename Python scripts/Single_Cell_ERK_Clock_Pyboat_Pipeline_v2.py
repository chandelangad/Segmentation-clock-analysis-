"""
Single-Cell ERK/Clock Tracking + pyBOAT Analysis Pipeline
==========================================================
Combines:
  - Step 1: Select cells via rotated-rectangle ROIs on TIF frames,
            filter by TrackID and minimum timepoints, export ERK/ClockNuc CSVs,
            SG-smooth both signals, and save smoothed CSVs + plots.
  - Step 2: Run pyBOAT wavelet analysis on the SG-smoothed ClockNuc CSV,
            compute ridge properties and Kuramoto R.
  - Step 3: Organise all outputs into an auto-incremented `cells_tracked_N/` folder.

Usage:
  python Single_Cell_ERK_Clock_Pyboat_Pipeline.py
  or 
  direcly click Run Python file on the right top corner
"""

# ============================================================
# 0. DEPENDENCIES
# ============================================================
import subprocess
import sys


def install_and_import(package, import_name=None):
    """Install package if not available, then import it."""
    try:
        __import__(import_name or package)
    except ImportError:
        print(f"Installing {package}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
        __import__(import_name or package)


for pkg in ["numpy", "pandas", "matplotlib", "tifffile", "openpyxl", "scipy", "pyboat"]:
    install_and_import(pkg)

print("All required packages are available.")

# ============================================================
# Standard imports
# ============================================================
import re
import shutil
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.path import Path as MplPath
import tifffile

from scipy.signal import savgol_filter
from pyboat import WAnalyzer


# ============================================================
# CONSTANTS
# ============================================================
REQUIRED_COLUMNS = [
    "TrackId",
    "TimeLapseIndex",
    "Entity",
    "ObjectId3D",
    "BFPNuc",
    "ClockNuc",
    "Nuclear_1CentroidX[µm]",
    "Nuclear_1CentroidY[µm]",
    "Nuclear_1CentroidZ[µm]",
    "CytoCount",
    "CytoMeanObjIntensity",
    "Volume_of_Nuc[µm³]",
]

PIXEL_SIZE_UM = 0.3          # 1 pixel = 0.3 µm

# pyBOAT parameters
DT          = 3.5            # minutes per sample
PERIODS     = np.linspace(20, 90, 70)   # minutes
T_C         = 100            # sinc detrending cutoff (min)
AMP_WIN     = 60             # amplitude envelope window (min)
POWER_THRESH        = 0
RIDGE_SMOOTH_WSIZE  = 10

SG_POLYORDER = 2
SG_NEIGHBORS = 3
SG_WINDOW    = 2 * SG_NEIGHBORS + 1    # 7


def savgol_prism_like(x: np.ndarray, window: int = 7, polyorder: int = 4) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    n = len(x)
    if n < 3:
        return x.copy()
    w = min(window, n if n % 2 == 1 else n - 1)
    if w < 3:
        return x.copy()
    p = min(polyorder, w - 1)
    if p < 1:
        return x.copy()
    return savgol_filter(x, window_length=w, polyorder=p, mode="interp")


def first_last_valid_idx(arr: np.ndarray):
    mask = ~np.isnan(arr)
    if not np.any(mask):
        return None, None
    start = int(np.argmax(mask))
    end   = int(len(arr) - 1 - np.argmax(mask[::-1]))
    return start, end


def smooth_pivot_df(df: pd.DataFrame) -> pd.DataFrame:
    """Apply Savitzky-Golay smoothing to each track column (valid segment only)."""
    out = df.copy()
    for col in df.columns:
        s_full = df[col].to_numpy(dtype=float)
        start_idx, end_idx = first_last_valid_idx(s_full)
        if start_idx is None:
            continue
        segment = s_full[start_idx:end_idx + 1]
        out.iloc[start_idx:end_idx + 1, out.columns.get_loc(col)] = savgol_prism_like(
            segment, window=SG_WINDOW, polyorder=SG_POLYORDER
        )
    return out


def compute_row_statistics(df: pd.DataFrame) -> pd.DataFrame:
    """Per-timepoint stats across cell columns (median, mean, SD, n_cells)."""
    return pd.DataFrame(
        {
            "TimeLapseIndex": df.index,
            "median": df.median(axis=1, skipna=True),
            "mean": df.mean(axis=1, skipna=True),
            "SD": df.std(axis=1, skipna=True),
            "n_cells": df.count(axis=1),
        }
    )


# ============================================================
# STEP 1 HELPERS  –  cell selection & CSV export
# ============================================================

def ask_for_files():
    root = tk.Tk()
    root.withdraw()

    excel_file = filedialog.askopenfilename(
        title="Select Excel file",
        filetypes=[("Excel files", "*.xlsx *.xls")]
    )
    if not excel_file:
        raise RuntimeError("No Excel file selected.")

    tif_file = filedialog.askopenfilename(
        title="Select nuclear channel TIF image file",
        filetypes=[("TIF files", "*.tif *.tiff")]
    )
    if not tif_file:
        raise RuntimeError("No TIF file selected.")

    return Path(excel_file), Path(tif_file)


def load_excel_data(excel_path: Path) -> pd.DataFrame:
    df = pd.read_excel(excel_path)
    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError("Excel file missing columns:\n" + "\n".join(missing))

    df["ERK activity"] = df["CytoMeanObjIntensity"] / df["BFPNuc"]
    df["CentroidX_pixels"] = df["Nuclear_1CentroidX[µm]"] / PIXEL_SIZE_UM
    df["CentroidY_pixels"] = df["Nuclear_1CentroidY[µm]"] / PIXEL_SIZE_UM
    return df


def ask_timepoints():
    print("Enter starting timepoint:", flush=True)
    start_tp = int(input("> ").strip())
    print("Enter number of breakpoints:", flush=True)
    n_breaks = int(input("> ").strip())
    breakpoints = []
    for i in range(n_breaks):
        print(f"Enter timepoint for breakpoint {i+1}:", flush=True)
        breakpoints.append(int(input("> ").strip()))
    selected_timepoints = [start_tp] + breakpoints
    return start_tp, breakpoints, selected_timepoints


def ask_min_timepoints():
    print("Enter minimum number of timepoints required for a TrackID to be included:", flush=True)
    return int(input("> ").strip())


def load_tif_data(tif_path: Path):
    with tifffile.TiffFile(tif_path) as tif:
        series = tif.series[0]
        arr    = series.asarray()
        axes   = series.axes
    return arr, axes


def extract_frame_2d(arr, axes, time_index):
    data = arr
    current_axes = list(axes)

    if "T" in current_axes:
        t_pos = current_axes.index("T")
        if time_index < 0 or time_index >= data.shape[t_pos]:
            raise IndexError(
                f"Requested timepoint {time_index} is outside range "
                f"(0–{data.shape[t_pos]-1})."
            )
        data = np.take(data, indices=time_index, axis=t_pos)
        current_axes.pop(t_pos)

    if "C" in current_axes:
        c_pos = current_axes.index("C")
        data  = np.take(data, indices=0, axis=c_pos)
        current_axes.pop(c_pos)

    if "Z" in current_axes:
        z_pos = current_axes.index("Z")
        data  = np.max(data, axis=z_pos)
        current_axes.pop(z_pos)

    data = np.squeeze(data)
    if data.ndim != 2:
        raise ValueError(
            f"Could not reduce image to 2D. Final shape: {data.shape}, "
            f"axes: {''.join(current_axes)}"
        )
    return data


def draw_rotated_rectangle(image2d, title_text="Draw rotated rectangle"):
    fig, ax = plt.subplots(figsize=(8, 8))
    ax.imshow(image2d, cmap="gray")
    ax.set_title(
        f"{title_text}\n"
        "Click 3 points:\n"
        "1) first corner\n"
        "2) second corner (along long edge)\n"
        "3) point to define width"
    )
    pts = plt.ginput(3, timeout=-1)
    plt.close(fig)

    if len(pts) != 3:
        raise RuntimeError("You must click exactly 3 points.")

    p1 = np.array(pts[0], dtype=float)
    p2 = np.array(pts[1], dtype=float)
    p3 = np.array(pts[2], dtype=float)

    edge      = p2 - p1
    edge_len  = np.linalg.norm(edge)
    if edge_len == 0:
        raise ValueError("First two points cannot be identical.")

    u    = edge / edge_len
    perp = np.array([-u[1], u[0]])
    signed_width = np.dot((p3 - p1), perp)

    p4     = p1 + signed_width * perp
    p3rect = p2 + signed_width * perp
    return np.vstack([p1, p2, p3rect, p4])


def points_inside_polygon(x_vals, y_vals, polygon):
    pts  = np.column_stack([x_vals, y_vals])
    path = MplPath(polygon)
    return path.contains_points(pts)


def run_step1(excel_path: Path, tif_path: Path) -> Path:
    """
    Run the cell-selection and filtering pipeline.
    Returns the path to the saved filtered ClockNuc CSV.
    """
    df = load_excel_data(excel_path)
    print("\nExcel loaded. ERK activity and pixel coordinates computed.")

    start_tp, breakpoints, selected_timepoints = ask_timepoints()
    min_tp = ask_min_timepoints()
    print(f"\nTimepoints for ROI drawing: {selected_timepoints}")
    print(f"Minimum timepoints per TrackID: {min_tp}")

    arr, axes = load_tif_data(tif_path)
    print(f"TIF loaded: shape={arr.shape}, axes='{axes}'")

    filtered_trackids_per_tp = {}
    all_filtered_trackids    = set()

    for i, tp in enumerate(selected_timepoints):
        print(f"\n--- Timepoint {tp} ---")
        frame2d = extract_frame_2d(arr, axes, tp - 1)
        polygon = draw_rotated_rectangle(frame2d, title_text=f"Timepoint {tp}: draw rotated rectangle")

        # Save a PNG of the rectangle only for the starting timepoint
        if i == 0:
            fig, ax = plt.subplots(figsize=(8, 8))
            ax.imshow(frame2d, cmap="gray")
            poly_closed = np.vstack([polygon, polygon[0]])
            ax.plot(poly_closed[:, 0], poly_closed[:, 1], "r-", linewidth=2)
            ax.set_title(f"Rectangle at starting timepoint {tp}")
            roi_png = excel_path.parent / f"{excel_path.stem}_ROI_timepoint{tp}.png"
            fig.savefig(roi_png, dpi=150, bbox_inches="tight")
            plt.close(fig)
            print(f"  ROI image saved: {roi_png}")

        df_tp = df[df["TimeLapseIndex"] == tp].copy()
        if df_tp.empty:
            print(f"  No rows for TimeLapseIndex={tp}")
            filtered_trackids_per_tp[tp] = set()
            continue

        inside_mask  = points_inside_polygon(
            df_tp["CentroidX_pixels"].to_numpy(),
            df_tp["CentroidY_pixels"].to_numpy(),
            polygon,
        )
        filtered_ids = set(df_tp.loc[inside_mask, "TrackId"].dropna().unique())
        filtered_trackids_per_tp[tp] = filtered_ids
        all_filtered_trackids.update(filtered_ids)
        print(f"  TrackIDs inside rectangle: {len(filtered_ids)}")

    if not all_filtered_trackids:
        raise RuntimeError("No TrackIDs found inside any rectangle.")

    print(f"\nTotal unique TrackIDs across all timepoints: {len(all_filtered_trackids)}")

    df_filtered   = df[df["TrackId"].isin(all_filtered_trackids)].copy()
    track_counts  = df_filtered.groupby("TrackId")["TimeLapseIndex"].nunique()
    valid_trackids = track_counts[track_counts >= min_tp].index
    df_filtered   = df_filtered[df_filtered["TrackId"].isin(valid_trackids)].copy()
    print(f"TrackIDs after minimum-timepoint filter: {len(valid_trackids)}")

    df_filtered.sort_values(["TimeLapseIndex", "TrackId"], inplace=True)

    out_dir   = excel_path.parent
    base_name = excel_path.stem

    erk_csv_df = df_filtered.pivot_table(
        index="TimeLapseIndex", columns="TrackId", values="ERK activity", aggfunc="first"
    )
    clock_csv_df = df_filtered.pivot_table(
        index="TimeLapseIndex", columns="TrackId", values="ClockNuc", aggfunc="first"
    )

    erk_out   = out_dir / f"{base_name}_filtered_ERK_activity.csv"
    clock_out = out_dir / f"{base_name}_filtered_ClockNuc.csv"
    erk_csv_df.to_csv(erk_out)
    clock_csv_df.to_csv(clock_out)

    erk_sg_df   = smooth_pivot_df(erk_csv_df)
    clock_sg_df = smooth_pivot_df(clock_csv_df)
    erk_sg_out   = out_dir / f"{base_name}_filtered_ERK_activity_SG_smoothed.csv"
    clock_sg_out = out_dir / f"{base_name}_filtered_ClockNuc_SG_smoothed.csv"
    erk_sg_df.to_csv(erk_sg_out)
    clock_sg_df.to_csv(clock_sg_out)

    clock_row_stats_out = out_dir / f"{base_name}_filtered_ClockNuc_SG_smoothed_row_statistics.csv"
    erk_row_stats_out   = out_dir / f"{base_name}_filtered_ERK_activity_SG_smoothed_row_statistics.csv"
    compute_row_statistics(clock_sg_df).to_csv(clock_row_stats_out, index=False)
    compute_row_statistics(erk_sg_df).to_csv(erk_row_stats_out, index=False)

    # --- ClockNuc plot (SG-smoothed) ---
    clock_plot_out = out_dir / f"{base_name}_ClockNuc_plot.png"
    plt.figure(figsize=(10, 6))
    for col in clock_sg_df.columns:
        plt.plot(clock_sg_df.index, clock_sg_df[col], alpha=0.3, linewidth=1)
    plt.plot(clock_sg_df.index, clock_sg_df.mean(axis=1),
             linewidth=3, linestyle="--", label="Average ClockNuc")
    plt.xlabel("TimeLapseIndex"); plt.ylabel("ClockNuc")
    plt.title("ClockNuc: single tracks and average (SG-smoothed)"); plt.legend(); plt.tight_layout()
    plt.savefig(clock_plot_out, dpi=300); plt.close()

    # --- ERK activity plot (SG-smoothed) ---
    erk_plot_out = out_dir / f"{base_name}_ERK_activity_plot.png"
    plt.figure(figsize=(10, 6))
    for col in erk_sg_df.columns:
        plt.plot(erk_sg_df.index, erk_sg_df[col], alpha=0.3, linewidth=1)
    plt.plot(erk_sg_df.index, erk_sg_df.mean(axis=1),
             linewidth=3, linestyle="--", label="Average ERK activity")
    plt.xlabel("TimeLapseIndex"); plt.ylabel("ERK activity")
    plt.title("ERK activity: single tracks and average (SG-smoothed)")
    plt.legend(); plt.ylim(0.9, 1.25); plt.tight_layout()
    plt.savefig(erk_plot_out, dpi=300); plt.close()

    # --- Summary CSV ---
    summary_rows = [
        {"Timepoint": tp, "TrackId": tid}
        for tp, tids in filtered_trackids_per_tp.items()
        for tid in sorted(tids)
    ]
    summary_out = out_dir / f"{base_name}_filtered_trackids_summary.csv"
    pd.DataFrame(summary_rows).to_csv(summary_out, index=False)

    print(f"\nERK CSV:              {erk_out}")
    print(f"ERK SG-smoothed CSV:  {erk_sg_out}")
    print(f"ClockNuc CSV:         {clock_out}")
    print(f"ClockNuc SG-smoothed: {clock_sg_out}")
    print(f"ClockNuc row stats:   {clock_row_stats_out}")
    print(f"ERK row stats:        {erk_row_stats_out}")
    print(f"Summary CSV:          {summary_out}")

    return clock_sg_out


# ============================================================
# STEP 2 HELPERS  –  pyBOAT wavelet analysis
# ============================================================

def compute_kuramoto_R(phase_df: pd.DataFrame) -> pd.DataFrame:
    R_vals = []
    for _, row in phase_df.iterrows():
        phases = row.dropna().to_numpy(dtype=float)
        R_vals.append(np.abs(np.mean(np.exp(1j * phases))) if len(phases) > 0 else np.nan)
    return pd.DataFrame({"R": R_vals}, index=phase_df.index)


def run_step2(clock_csv: Path):
    """Run pyBOAT analysis on the filtered ClockNuc CSV."""
    print(f"\nRunning pyBOAT on: {clock_csv}")

    df_raw    = pd.read_csv(clock_csv)
    first_col = df_raw.iloc[:, 0]

    if first_col.notna().sum() > 0:
        df_raw = df_raw.iloc[:, 1:]
        print("Detected time column → excluded from analysis")

    df_raw.columns = [f"Cell_{i+1}" for i in range(df_raw.shape[1])]
    df_num = df_raw.apply(lambda c: pd.to_numeric(c, errors="coerce"))

    label_row     = pd.DataFrame([df_num.columns], columns=df_num.columns)
    df_with_label = pd.concat([label_row, df_num], ignore_index=True)

# object dtype so row 0 can hold column labels (Cell_1, ...) alongside numeric values
    out_periods = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)
    out_phase   = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)
    out_amp     = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)
    out_power   = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)
    out_freq    = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)
    out_sg      = pd.DataFrame(index=df_with_label.index, columns=df_with_label.columns, dtype=object)

    for out_df in [out_periods, out_phase, out_amp, out_power, out_freq, out_sg]:
        out_df.iloc[0, :] = df_num.columns

    errors = []

    for col in df_num.columns:
        s_full              = df_num[col].to_numpy(dtype=float)
        start_idx, end_idx  = first_last_valid_idx(s_full)

        if start_idx is None:
            errors.append((col, "All NaN")); continue

        signal = s_full[start_idx:end_idx + 1]
        n      = len(signal)

        if n < 5:
            errors.append((col, f"Too short (n={n})")); continue

        try:
            sg_signal = signal  # SG-smoothed in Step 1
            out_sg.loc[1 + start_idx:1 + end_idx, col] = sg_signal

            wAn      = WAnalyzer(PERIODS, DT, time_unit_label="min")
            trend    = wAn.sinc_smooth(sg_signal, T_c=T_C)
            detrended = sg_signal - trend
            norm_signal = wAn.normalize_amplitude(detrended, window_size=AMP_WIN)

            wAn.compute_spectrum(norm_signal, do_plot=False)
            wAn.get_maxRidge(power_thresh=POWER_THRESH, smoothing_wsize=RIDGE_SMOOTH_WSIZE)
            rd = wAn.ridge_data

            if rd is None or len(rd) == 0:
                errors.append((col, "Empty ridge")); continue

            times      = rd["time"].to_numpy(dtype=float)
            sample_idx = np.rint(times / DT).astype(int)
            valid      = (sample_idx >= 0) & (sample_idx < n)

            if not np.any(valid):
                errors.append((col, "Ridge times outside signal")); continue

            sample_idx = sample_idx[valid]
            out_rows   = 1 + start_idx + sample_idx

            out_periods.loc[out_rows, col] = rd.loc[valid, "periods"].to_numpy()
            out_phase.loc[out_rows, col]   = rd.loc[valid, "phase"].to_numpy()
            out_amp.loc[out_rows, col]     = rd.loc[valid, "amplitude"].to_numpy()
            out_power.loc[out_rows, col]   = rd.loc[valid, "power"].to_numpy()
            out_freq.loc[out_rows, col]    = rd.loc[valid, "frequencies"].to_numpy()

        except Exception as e:
            errors.append((col, repr(e)))

    # Kuramoto R
    phase_numeric        = out_phase.iloc[1:, :].apply(pd.to_numeric, errors="coerce")
    kuramoto_R           = compute_kuramoto_R(phase_numeric)
    kuramoto_R_with_label = pd.concat(
        [pd.DataFrame({"R": ["Kuramoto_R"]}), kuramoto_R], ignore_index=True
    )

    # Save outputs
    out_dir     = clock_csv.parent
    base        = clock_csv.stem
    results_dir = out_dir / "Pyboat results"
    results_dir.mkdir(exist_ok=True)

    out_sg.to_csv(results_dir / f"{base}_SG_smoothed.csv", index=False, header=False)
    out_periods.to_excel(results_dir / f"{base}_ridge_periods.xlsx",    index=False, header=False)
    out_phase.to_excel(results_dir   / f"{base}_ridge_phase.xlsx",      index=False, header=False)
    out_amp.to_excel(results_dir     / f"{base}_ridge_amplitude.xlsx",  index=False, header=False)
    out_power.to_excel(results_dir   / f"{base}_ridge_power.xlsx",      index=False, header=False)
    out_freq.to_excel(results_dir    / f"{base}_ridge_frequencies.xlsx",index=False, header=False)
    kuramoto_R_with_label.to_csv(results_dir / f"{base}_Kuramoto_R.csv", index=False, header=False)
    pd.DataFrame(errors, columns=["Column", "Error"]).to_csv(
        results_dir / f"{base}_ridge_errors.csv", index=False
    )

    print(f"pyBOAT results saved to: {results_dir}")
    print(f"  {len(df_num.columns)} columns processed, {len(errors)} errors.")


# ============================================================
# STEP 3 HELPERS  –  organise outputs into cells_tracked_N/
# ============================================================

def add_run_suffix(path: Path, run_idx: int) -> str:
    return f"{path.stem}_{run_idx}{path.suffix}"


def create_next_cells_tracked_dir(root: Path) -> tuple[int, Path]:
    existing_idxs = []
    for p in root.iterdir():
        if not p.is_dir():
            continue
        m = re.fullmatch(r"cells_tracked_(\d+)", p.name)
        if m:
            existing_idxs.append(int(m.group(1)))
    next_idx = (max(existing_idxs) + 1) if existing_idxs else 1
    run_dir  = root / f"cells_tracked_{next_idx}"
    run_dir.mkdir(parents=True, exist_ok=False)
    return next_idx, run_dir


def collect_outputs(clock_csv: Path, run_idx: int, run_dir: Path):
    out_dir    = clock_csv.parent
    clock_stem = clock_csv.stem
    base_name  = clock_stem.removesuffix("_filtered_ClockNuc_SG_smoothed").removesuffix("_filtered_ClockNuc")

    step1_files = [
        out_dir / f"{base_name}_filtered_ERK_activity.csv",
        out_dir / f"{base_name}_filtered_ERK_activity_SG_smoothed.csv",
        out_dir / f"{base_name}_filtered_ClockNuc.csv",
        out_dir / f"{base_name}_filtered_ClockNuc_SG_smoothed.csv",
        out_dir / f"{base_name}_filtered_ClockNuc_SG_smoothed_row_statistics.csv",
        out_dir / f"{base_name}_filtered_ERK_activity_SG_smoothed_row_statistics.csv",
        out_dir / f"{base_name}_ClockNuc_plot.png",
        out_dir / f"{base_name}_ERK_activity_plot.png",
        out_dir / f"{base_name}_filtered_trackids_summary.csv",
    ]

    # Also collect the ROI image saved during step 1
    for roi_png in out_dir.glob(f"{base_name}_ROI_timepoint*.png"):
        step1_files.append(roi_png)

    moved = []
    for src in step1_files:
        if src.exists():
            dst = run_dir / add_run_suffix(src, run_idx)
            shutil.move(str(src), str(dst))
            moved.append(dst)

    pyboat_src_dir = out_dir / "Pyboat results"
    pyboat_dst_dir = run_dir / f"Pyboat_results_{run_idx}"
    if pyboat_src_dir.exists():
        pyboat_dst_dir.mkdir(parents=True, exist_ok=True)
        for src in sorted(pyboat_src_dir.glob(f"{clock_stem}*")):
            if src.is_file():
                dst = pyboat_dst_dir / add_run_suffix(src, run_idx)
                shutil.move(str(src), str(dst))
                moved.append(dst)
        try:
            if not any(pyboat_src_dir.iterdir()):
                pyboat_src_dir.rmdir()
        except Exception:
            pass

    manifest = run_dir / f"moved_files_manifest_{run_idx}.txt"
    with manifest.open("w", encoding="utf-8") as fh:
        for p in moved:
            fh.write(str(p) + "\n")

    print(f"\nOutputs collected in: {run_dir}")
    print(f"Manifest:             {manifest}")


# ============================================================
# MAIN
# ============================================================
def main():
    try:
        # --- File selection ---
        print("Select input files...")
        excel_path, tif_path = ask_for_files()
        print(f"Excel: {excel_path}")
        print(f"TIF:   {tif_path}")

        # --- Step 1: cell selection + CSV export ---
        print("\n=== Step 1/3: Cell selection and filtering ===")
        clock_csv = run_step1(excel_path, tif_path)
        print(f"\nFiltered ClockNuc CSV: {clock_csv}")

        # --- Step 2: pyBOAT wavelet analysis ---
        print("\n=== Step 2/3: pyBOAT wavelet analysis ===")
        run_step2(clock_csv)

        # --- Step 3: organise outputs ---
        print("\n=== Step 3/3: Organising outputs ===")
        run_idx, run_dir = create_next_cells_tracked_dir(clock_csv.parent)
        collect_outputs(clock_csv, run_idx, run_dir)

        print("\nAll steps completed successfully.")

        try:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Done", f"Pipeline finished.\nOutputs in:\n{run_dir}")
        except Exception:
            pass

    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
