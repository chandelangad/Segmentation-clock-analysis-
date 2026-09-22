"""
Somite Length Analysis Script (summary-statistics input)
--------------------------------------------------------
- Reads xlsx or csv file with multiple sheets (first sheet = control / DMSO)
- Each sheet has 4 columns, read by POSITION (header names don't matter):
      col 0 = somite number (time axis)
      col 1 = mean length
      col 2 = SD
      col 3 = count (n)
- Performs Welch's t-test FROM SUMMARY STATS for each somite vs DMSO control
  (scipy.stats.ttest_ind_from_stats, equal_var=False), no multiple-comparison
  correction.
- Plots mean ± error per condition with significance markers.
  ERROR_BAR selects whether the band is SEM (= SD/sqrt(n)) or raw SD.
- Uses GraphPad Prism "Colors" scheme
- Axis limits are computed once across ALL conditions (shared across all plots)
- Control is plotted over its full range regardless of where drug data ends
- Significance markers are stacked vertically to prevent overlap
- No legend shown
"""

import sys
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from scipy import stats

# ── Error-bar type for the shaded band / axis padding ─────────────────────────
#   "SEM" -> SD / sqrt(n)   (matches the original script's plotting behaviour)
#   "SD"  -> raw SD from column 3
# The t-test itself always uses SD + n directly and is unaffected by this.
ERROR_BAR = "SEM"

# ── GraphPad Prism "Colors" scheme ────────────────────────────────────────────
PRISM_COLORS = [
    "#0000FF",  # Blue        – Control / DMSO
    "#FF0000",  # Red         – Drug 1
    "#00C000",  # Green       – Drug 2
    "#AD07E3",  # Purple      – Drug 3
    "#FF8000",  # Orange      – Drug 4
    "#000000",  # Black       – Drug 5
    "#94641F",  # Brown       – Drug 6
    "#000080",  # Navy        – Drug 7
]

# ── Significance label helper ─────────────────────────────────────────────────
def pval_to_stars(p):
    if p < 0.0001:
        return "****"
    elif p < 0.001:
        return "***"
    elif p < 0.01:
        return "**"
    elif p < 0.05:
        return "*"
    else:
        return "ns"


# ── Load data ─────────────────────────────────────────────────────────────────
def load_data(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    if ext in [".xlsx", ".xls"]:
        xl = pd.ExcelFile(filepath)
        sheets = xl.sheet_names
        data = {name: xl.parse(name, index_col=None) for name in sheets}
    elif ext == ".csv":
        df = pd.read_csv(filepath, index_col=None)
        sheets = ["Control"]
        data = {"Control": df}
    else:
        raise ValueError(f"Unsupported file type: {ext}")
    return sheets, data


# ── Read per-somite summary stats from the 4-column layout ────────────────────
def compute_stats(df):
    """
    Returns {somite (float): (mean, err, sd, n)} where `err` is the plotting
    error bar (SEM or SD depending on ERROR_BAR). Rows with a non-numeric or
    missing somite number / mean are skipped.
    """
    if df.shape[1] < 4:
        raise ValueError(
            f"Expected 4 columns (somite, mean, SD, count) but found {df.shape[1]}."
        )

    result = {}
    for _, row in df.iterrows():
        # --- somite number (col 0) ---
        try:
            x_val = float(str(row.iloc[0]).strip())
        except (ValueError, AttributeError, TypeError):
            continue

        # --- mean (col 1) ---
        try:
            mean = float(row.iloc[1])
        except (ValueError, TypeError):
            continue
        if np.isnan(mean):
            continue

        # --- SD (col 2) ---
        try:
            sd = float(row.iloc[2])
        except (ValueError, TypeError):
            sd = np.nan

        # --- count (col 3) ---
        try:
            n = float(row.iloc[3])
        except (ValueError, TypeError):
            n = np.nan

        # --- error bar for plotting ---
        if ERROR_BAR.upper() == "SEM" and not np.isnan(sd) and n and n > 0:
            err = sd / np.sqrt(n)
        elif not np.isnan(sd):
            err = sd
        else:
            err = 0.0

        result[x_val] = (mean, err, sd, n)
    return result


# ── Run Welch's t-test (from summary stats) per somite ────────────────────────
def run_ttests(control_stats, drug_stats):
    results = {}
    common_somites = [s for s in control_stats.keys() if s in drug_stats]
    for s in common_somites:
        c_mean, _, c_sd, c_n = control_stats[s]
        d_mean, _, d_sd, d_n = drug_stats[s]
        if (np.isnan(c_sd) or np.isnan(d_sd) or np.isnan(c_n) or np.isnan(d_n)
                or c_n < 2 or d_n < 2):
            results[s] = (np.nan, np.nan, "")
            continue
        t, p = stats.ttest_ind_from_stats(
            mean1=c_mean, std1=c_sd, nobs1=int(c_n),
            mean2=d_mean, std2=d_sd, nobs2=int(d_n),
            equal_var=False,
        )
        results[s] = (t, p, pval_to_stars(p))
    return results


# ── Compute global axis limits across ALL conditions in a file ────────────────
def compute_global_axis_limits(control_stats, drug_stats_dict,
                                pad_frac=0.08, sig_headroom_frac=0.18):
    """
    Pool means and error bars from every condition and every somite to find a
    single axis range shared by all plots. Extra headroom above max is
    provided for stacked significance markers.
    X range is taken from the union of ALL somite numbers across all sheets.
    """
    all_means, all_errs, all_somites = [], [], []

    for stats_dict in [control_stats] + list(drug_stats_dict.values()):
        for s, vals in stats_dict.items():
            all_means.append(vals[0])
            all_errs.append(vals[1])
            all_somites.append(s)

    all_means = np.asarray(all_means, dtype=float)
    all_errs  = np.asarray(all_errs, dtype=float)

    data_min = np.min(all_means - all_errs)
    data_max = np.max(all_means + all_errs)
    data_range = data_max - data_min
    if data_range == 0:
        data_range = abs(data_max) if data_max != 0 else 1.0

    y_min = data_min - pad_frac * data_range
    y_max = data_max + sig_headroom_frac * data_range

    # Round to nice numbers
    magnitude = 10 ** np.floor(np.log10(data_range))
    step = magnitude if data_range / magnitude < 5 else 2 * magnitude
    y_min_nice = np.floor(y_min / step) * step
    y_max_nice = np.ceil(y_max / step) * step

    # Global x range: union of all somite numbers across every sheet
    x_all = np.array(sorted(set(all_somites)), dtype=float)
    x_pad = (x_all[-1] - x_all[0]) * 0.03 if len(x_all) > 1 else 0.5
    x_min_nice = x_all[0]  - x_pad
    x_max_nice = x_all[-1] + x_pad

    return y_min_nice, y_max_nice, x_min_nice, x_max_nice


# ── Plot one comparison (control vs one drug) ─────────────────────────────────
def plot_comparison(control_name, drug_name,
                    control_stats, drug_stats, ttest_results,
                    ctrl_color, drug_color, out_dir,
                    global_y_lim, global_x_lim):

    # Control is plotted over its FULL range of valid somites (not clipped to drug range)
    ctrl_somites  = sorted(control_stats.keys())
    drug_somites  = sorted(drug_stats.keys())
    # Somites where a t-test was run (intersection)
    common_somites = sorted([s for s in control_stats.keys() if s in drug_stats])

    ctrl_means_full = np.array([control_stats[s][0] for s in ctrl_somites])
    ctrl_errs_full  = np.array([control_stats[s][1] for s in ctrl_somites])
    drug_means      = np.array([drug_stats[s][0]    for s in drug_somites])
    drug_errs       = np.array([drug_stats[s][1]    for s in drug_somites])

    # Means/errs at common somites only (needed for star placement)
    ctrl_means_common = np.array([control_stats[s][0] for s in common_somites])
    ctrl_errs_common  = np.array([control_stats[s][1] for s in common_somites])
    drug_means_common = np.array([drug_stats[s][0]    for s in common_somites])
    drug_errs_common  = np.array([drug_stats[s][1]    for s in common_somites])

    x_ctrl = np.array(ctrl_somites, dtype=float)
    x_drug = np.array(drug_somites, dtype=float)
    x_common = np.array(common_somites, dtype=float)

    # ── Use shared global axis limits ─────────────────────────────────────────
    y_min, y_max = global_y_lim
    x_min_auto, x_max_auto = global_x_lim
    y_range = y_max - y_min

    fig, ax = plt.subplots(figsize=(10, 7))

    # ── Plot control over its full range ──────────────────────────────────────
    markers = ['o', 's']
    ax.plot(x_ctrl, ctrl_means_full, color=ctrl_color, linewidth=2.2,
            marker=markers[0], markersize=8, zorder=3)
    ax.fill_between(x_ctrl, ctrl_means_full - ctrl_errs_full,
                    ctrl_means_full + ctrl_errs_full,
                    color=ctrl_color, alpha=0.18, zorder=2,
                    linestyle='dotted', edgecolor=ctrl_color, linewidth=1.2)

    # ── Plot drug over its own range ──────────────────────────────────────────
    ax.plot(x_drug, drug_means, color=drug_color, linewidth=2.2,
            marker=markers[1], markersize=8, zorder=3)
    ax.fill_between(x_drug, drug_means - drug_errs, drug_means + drug_errs,
                    color=drug_color, alpha=0.18, zorder=2,
                    linestyle='dotted', edgecolor=drug_color, linewidth=1.2)

    # ── Significance markers with vertical stacking to avoid overlap ──────────
    min_gap = y_range * 0.055   # ~5.5% of y range per star row
    base_offset = y_range * 0.02  # small gap above the error band

    used_y = {}   # x_pos (rounded) -> highest y used so far

    sig_items = []
    for idx, s in enumerate(common_somites):
        stars = ttest_results.get(s, (None, None, ""))[2]
        if stars and stars != "ns":
            upper = max(ctrl_means_common[idx] + ctrl_errs_common[idx],
                        drug_means_common[idx] + drug_errs_common[idx])
            sig_items.append((x_common[idx], upper, stars))

    for x_pos, upper, stars in sig_items:
        x_key = round(x_pos, 6)
        desired_y = upper + base_offset
        if x_key in used_y:
            desired_y = max(desired_y, used_y[x_key] + min_gap)
        ax.text(x_pos, desired_y, stars, ha='center', va='bottom',
                fontsize=20, color='black')
        used_y[x_key] = desired_y

    # ── Styling ───────────────────────────────────────────────────────────────
    ax.set_xlabel("Somite No.", fontsize=30, labelpad=10)
    ax.set_ylabel("Length (µm)", fontsize=30, labelpad=10)
    ax.set_title(f"{drug_name}", fontsize=26, pad=20)

    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_linewidth(1.8)
    ax.spines['bottom'].set_linewidth(1.8)

    # ── X-axis ticks ──────────────────────────────────────────────────────────
    x_span = x_max_auto - x_min_auto
    for interval in [1, 2, 5, 10]:
        if x_span / interval <= 8:
            major_interval = interval
            break
    else:
        major_interval = round(x_span / 6)

    ax.xaxis.set_major_locator(ticker.MultipleLocator(major_interval))
    ax.xaxis.set_minor_locator(ticker.MultipleLocator(max(major_interval / 2, 0.5)))
    ax.tick_params(axis='x', which='minor', length=3)
    ax.set_xlim(x_min_auto, x_max_auto)

    ax.tick_params(axis='both', which='major', labelsize=26, length=6, width=1.5)
    ax.set_ylim(y_min, y_max)

    # No legend
    ax.legend().set_visible(False)

    plt.tight_layout()

    safe_name = drug_name.replace(" ", "_").replace("/", "-")
    out_path = os.path.join(out_dir, f"{safe_name}_vs_{control_name}.pdf")
    fig.savefig(out_path, dpi=300, bbox_inches='tight')

    png_path = out_path.replace(".pdf", ".png")
    fig.savefig(png_path, dpi=300, bbox_inches='tight')

    plt.close(fig)
    print(f"  Saved: {out_path}")
    print(f"  Saved: {png_path}")
    return out_path


# ── Save stats table ──────────────────────────────────────────────────────────
def save_stats_table(all_results, control_stats, drug_stats_dict, out_dir):
    rows = []
    for drug_name, ttest_res in all_results.items():
        dstats = drug_stats_dict[drug_name]
        for somite, (t, p, stars) in ttest_res.items():
            c = control_stats.get(somite)
            d = dstats.get(somite)
            rows.append({
                "Condition":    drug_name,
                "Somite":       somite,
                "Control_Mean": c[0] if c else np.nan,
                "Control_SD":   c[2] if c else np.nan,
                "Control_n":    c[3] if c else np.nan,
                "Drug_Mean":    d[0] if d else np.nan,
                "Drug_SD":      d[2] if d else np.nan,
                "Drug_n":       d[3] if d else np.nan,
                "t_statistic":  round(t, 4) if not np.isnan(t) else np.nan,
                "p_value":      round(p, 6) if not np.isnan(p) else np.nan,
                "Significance": stars,
            })
    df_out = pd.DataFrame(rows)
    csv_path = os.path.join(out_dir, "welch_ttest_from_stats_results.csv")
    df_out.to_csv(csv_path, index=False)
    print(f"  Saved stats table: {csv_path}")
    return csv_path


# ── Main ──────────────────────────────────────────────────────────────────────
def main(filepath):
    out_dir = os.path.dirname(os.path.abspath(filepath))
    print(f"\nLoading: {filepath}")

    sheets, data = load_data(filepath)

    if len(sheets) < 2:
        print("Need at least 2 sheets (DMSO control + 1 drug condition).")
        sys.exit(1)

    control_name = sheets[0]
    drug_names   = sheets[1:]

    print(f"Control (DMSO) sheet : {control_name}")
    print(f"Drug conditions      : {drug_names}")
    print(f"Error-bar type       : {ERROR_BAR}\n")

    control_stats = compute_stats(data[control_name])

    all_ttest_results = {}
    drug_stats_dict   = {}

    # ── First pass: read all drug stats ──────────────────────────────────────
    for drug_name in drug_names:
        drug_stats_dict[drug_name] = compute_stats(data[drug_name])

    # ── Compute global axis limits across ALL conditions ──────────────────────
    global_y_lim, global_x_lim = (
        lambda lims: (lims[:2], lims[2:])
    )(compute_global_axis_limits(control_stats, drug_stats_dict))
    print(f"Global y-limits : {global_y_lim[0]:.2f} – {global_y_lim[1]:.2f} µm")
    print(f"Global x-limits : {global_x_lim[0]:.1f} – {global_x_lim[1]:.1f}\n")

    # ── Second pass: run stats and plot ──────────────────────────────────────
    for i, drug_name in enumerate(drug_names):
        drug_stats = drug_stats_dict[drug_name]

        ttest_res = run_ttests(control_stats, drug_stats)
        all_ttest_results[drug_name] = ttest_res

        ctrl_color = PRISM_COLORS[0]
        drug_color = PRISM_COLORS[(i + 1) % len(PRISM_COLORS)]

        print(f"Plotting: {control_name} vs {drug_name}")
        plot_comparison(
            control_name, drug_name,
            control_stats, drug_stats, ttest_res,
            ctrl_color, drug_color,
            out_dir,
            global_y_lim=global_y_lim,
            global_x_lim=global_x_lim,
        )

    save_stats_table(all_ttest_results, control_stats, drug_stats_dict, out_dir)
    print("\nDone!")


if __name__ == "__main__":
    print("=" * 50)
    print("  Somite Length Analysis (summary-stats input)")
    print("=" * 50)

    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.wm_attributes("-topmost", True)
        filepath = filedialog.askopenfilename(
            title="Select your data file",
            filetypes=[("Excel / CSV files", "*.xlsx *.xls *.csv"),
                       ("All files", "*.*")]
        )
        root.destroy()
        if not filepath:
            print("No file selected. Exiting.")
            sys.exit(0)
    except Exception:
        filepath = input("Enter path to your .xlsx or .csv file:\n> ").strip().strip('"\'')

    if not os.path.isfile(filepath):
        print(f"\nFile not found: {filepath}")
        sys.exit(1)

    main(filepath)
