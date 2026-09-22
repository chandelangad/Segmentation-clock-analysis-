"""
Somite Length Analysis Script
------------------------------
- Reads xlsx or csv file with multiple sheets (first sheet = control)
- Each sheet: column 1 = somite number, remaining columns = embryo measurements
- Performs two-way ANOVA (Condition x Somite) separately for each drug vs control
- Pairwise comparisons at each somite use pooled MSE from the full ANOVA model
- Plots mean ± SEM per condition with significance markers
- Uses GraphPad Prism "Colors" scheme
- Axis limits are computed once across ALL conditions so every plot is directly comparable
- Significance marker positions scale with the shared axis limits
"""

import sys
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from scipy import stats
from statsmodels.formula.api import ols
from statsmodels.stats.anova import anova_lm

# ── GraphPad Prism "Colors" scheme ────────────────────────────────────────────
PRISM_COLORS = [
    "#0000FF",  # Blue        – Control
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


# ── Compute per-somite stats ──────────────────────────────────────────────────
def compute_stats(df):
    x_col = df.columns[0]
    embryo_cols = df.columns[1:]

    result = {}
    for _, row in df.iterrows():
        x_val = row[x_col]

        if '*' in str(x_val):
            continue
        try:
            x_val = float(str(x_val).strip())
        except ValueError:
            continue

        raw = row[embryo_cols].dropna()
        def to_float(v):
            if '*' in str(v):
                return np.nan
            try:
                return float(str(v).strip())
            except ValueError:
                return np.nan
        vals = np.array([to_float(v) for v in raw])
        vals = vals[~np.isnan(vals)]
        if len(vals) == 0:
            continue
        mean = np.mean(vals)
        sem = stats.sem(vals) if len(vals) > 1 else 0.0
        result[x_val] = (mean, sem, vals)
    return result


# ── Run two-way ANOVA + pairwise comparison per somite ───────────────────────
def run_ttests(control_stats, drug_stats):
    rows = []
    common_somites = [s for s in control_stats.keys() if s in drug_stats]
    for s in common_somites:
        for v in control_stats[s][2]:
            rows.append({"Length": v, "Condition": "Control", "Somite": s})
        for v in drug_stats[s][2]:
            rows.append({"Length": v, "Condition": "Drug", "Somite": s})

    df = pd.DataFrame(rows)
    df["Somite"] = df["Somite"].astype("category")
    df["Condition"] = df["Condition"].astype("category")

    model = ols("Length ~ C(Condition) + C(Somite) + C(Condition):C(Somite)",
                data=df).fit()

    results = {}
    mse = model.mse_resid

    for s in common_somites:
        ctrl_vals = control_stats[s][2]
        drug_vals = drug_stats[s][2]
        if len(ctrl_vals) < 2 or len(drug_vals) < 2:
            results[s] = (np.nan, np.nan, "")
            continue

        mean_diff = np.mean(ctrl_vals) - np.mean(drug_vals)
        se = np.sqrt(mse * (1.0 / len(ctrl_vals) + 1.0 / len(drug_vals)))
        df_resid = model.df_resid
        t_stat = mean_diff / se
        p_val = 2 * stats.t.sf(np.abs(t_stat), df=df_resid)
        results[s] = (t_stat, p_val, pval_to_stars(p_val))

    return results



# ── Compute global axis limits across ALL conditions in a file ────────────────
def compute_global_axis_limits(control_stats, drug_stats_dict,
                                pad_frac=0.08, sig_headroom_frac=0.14):
    """
    Pool means and SEMs from every condition (control + all drugs) and every
    somite to find a single y-axis range shared by all plots in the file.
    Also computes the global x range from the union of all somite numbers.
    """
    all_means, all_sems, all_somites = [], [], []

    for stats_dict in [control_stats] + list(drug_stats_dict.values()):
        for s, (mean, sem, _) in stats_dict.items():
            all_means.append(mean)
            all_sems.append(sem)
            all_somites.append(s)

    all_means = np.asarray(all_means)
    all_sems  = np.asarray(all_sems)

    data_min = np.min(all_means - all_sems)
    data_max = np.max(all_means + all_sems)
    data_range = data_max - data_min

    y_min = data_min - pad_frac * data_range
    y_max = data_max + sig_headroom_frac * data_range

    # Round to "nice" numbers
    magnitude = 10 ** np.floor(np.log10(data_range))
    step = magnitude if data_range / magnitude < 5 else 2 * magnitude
    y_min_nice = np.floor(y_min / step) * step
    y_max_nice = np.ceil(y_max / step) * step

    # Global x range
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

    common_somites = sorted([s for s in control_stats.keys() if s in drug_stats])

    ctrl_means = np.array([control_stats[s][0] for s in common_somites])
    ctrl_sems  = np.array([control_stats[s][1] for s in common_somites])
    drug_means = np.array([drug_stats[s][0] for s in common_somites])
    drug_sems  = np.array([drug_stats[s][1] for s in common_somites])

    x = np.array(common_somites, dtype=float)
    x_numeric = np.issubdtype(x.dtype, np.number)

    # ── Use shared global axis limits ─────────────────────────────────────────
    y_min, y_max = global_y_lim
    x_min_auto, x_max_auto = global_x_lim

    # Significance marker offset: 2% of the shared y-range
    y_range = y_max - y_min
    y_offset = 0.02 * y_range

    fig, ax = plt.subplots(figsize=(10, 7))

    # ── Plot lines + error bands ──────────────────────────────────────────────
    markers = ['o', 's', '^', 'D', 'v']
    for idx2, (means, sems, color, label) in enumerate([
        (ctrl_means, ctrl_sems, ctrl_color, control_name),
        (drug_means, drug_sems, drug_color, drug_name),
    ]):
        marker = markers[idx2 % len(markers)]
        ax.plot(x, means, color=color, linewidth=2.2, label=label,
                marker=marker, markersize=8, zorder=3)
        ax.fill_between(x, means - sems, means + sems,
                        color=color, alpha=0.18, zorder=2,
                        linestyle='dotted', edgecolor=color, linewidth=1.2)

    # ── Significance markers ──────────────────────────────────────────────────
    for idx, s in enumerate(common_somites):
        stars = ttest_results.get(s, (None, None, ""))[2]
        if stars and stars != "ns":
            x_pos = x[idx] if x_numeric else idx
            # Place star just above whichever line + SEM band is higher
            upper_ctrl = ctrl_means[idx] + ctrl_sems[idx]
            upper_drug = drug_means[idx] + drug_sems[idx]
            y_pos = max(upper_ctrl, upper_drug) + y_offset
            ax.text(x_pos, y_pos, stars, ha='center', va='bottom',
                    fontsize=22, color='black')

    # ── Styling ───────────────────────────────────────────────────────────────
    ax.set_xlabel("Somite No.", fontsize=28, labelpad=10)
    ax.set_ylabel("Length (µm)", fontsize=28, labelpad=10)
    ax.set_title(f"{drug_name}", fontsize=28, pad=14)

    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_linewidth(1.8)
    ax.spines['bottom'].set_linewidth(1.8)

    # ── X-axis ticks ──────────────────────────────────────────────────────────
    if x_numeric:
        x_span = x[-1] - x[0]
        # Pick a major tick interval that gives ~5-8 ticks
        for interval in [1, 2, 5, 10]:
            if x_span / interval <= 8:
                major_interval = interval
                break
        else:
            major_interval = round(x_span / 6)

        ax.xaxis.set_major_locator(ticker.MultipleLocator(major_interval))
        ax.xaxis.set_minor_locator(ticker.MultipleLocator(major_interval / 2))
        ax.tick_params(axis='x', which='minor', length=3)
        ax.set_xlim(11,20)
    else:
        ax.set_xticks(range(len(x)))
        ax.set_xticklabels(common_somites,
                           rotation=45 if len(x) > 15 else 0,
                           ha='right' if len(x) > 15 else 'center')

    ax.tick_params(axis='both', which='major', labelsize=24, length=6, width=1.5)
    ax.set_ylim(y_min, y_max)

    #ax.legend(frameon=False, fontsize=18, loc='upper right',
    #          bbox_to_anchor=(1.0, 0.75))

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
            ctrl_n = len(control_stats[somite][2]) if somite in control_stats else np.nan
            drug_n = len(dstats[somite][2]) if somite in dstats else np.nan
            rows.append({
                "Condition": drug_name,
                "Somite": somite,
                "Control_Mean": control_stats[somite][0] if somite in control_stats else np.nan,
                "Control_SEM":  control_stats[somite][1] if somite in control_stats else np.nan,
                "Control_n":    ctrl_n,
                "Drug_Mean":    dstats[somite][0] if somite in dstats else np.nan,
                "Drug_SEM":     dstats[somite][1] if somite in dstats else np.nan,
                "Drug_n":       drug_n,
                "t_statistic_ANOVA_pooled":  round(t, 4) if not np.isnan(t) else np.nan,
                "p_value":      round(p, 6) if not np.isnan(p) else np.nan,
                "Significance": stars,
            })
    df_out = pd.DataFrame(rows)
    csv_path = os.path.join(out_dir, "twoway_anova_pairwise_results.csv")
    df_out.to_csv(csv_path, index=False)
    print(f"  Saved stats table: {csv_path}")
    return csv_path


# ── Main ──────────────────────────────────────────────────────────────────────
def main(filepath):
    out_dir = os.path.dirname(os.path.abspath(filepath))
    print(f"\nLoading: {filepath}")

    sheets, data = load_data(filepath)

    if len(sheets) < 2:
        print("Need at least 2 sheets (control + 1 drug condition).")
        sys.exit(1)

    control_name = sheets[0]
    drug_names   = sheets[1:]

    print(f"Control sheet : {control_name}")
    print(f"Drug conditions: {drug_names}\n")

    control_stats = compute_stats(data[control_name])

    all_ttest_results = {}
    drug_stats_dict   = {}

    # ── First pass: compute all drug stats ───────────────────────────────────
    for drug_name in drug_names:
        drug_stats_dict[drug_name] = compute_stats(data[drug_name])

    # ── Compute global axis limits across ALL conditions ──────────────────────
    global_y_lim, global_x_lim = (
        lambda lims: (lims[:2], lims[2:])
    )(compute_global_axis_limits(control_stats, drug_stats_dict))
    print(f"Global y-limits : {global_y_lim[0]:.1f} – {global_y_lim[1]:.1f} µm")
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
    print("  Somite Length Analysis")
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
