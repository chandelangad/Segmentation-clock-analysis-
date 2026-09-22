// ==========================================================================
//  Shrink-shift kymograph
//  --------------------------------------------------------------------------
//  Rule: going down the rows (time), whenever a row's data is shorter than the
//  row before it, shift this row AND all following rows to the RIGHT by the
//  length difference (cumulative). The right side is never restricted — the
//  output canvas grows as wide as needed.
//  Run with your movie as the active image (as in your current workflow).
//  Saves the ROIs and the kymograph next to the source file, filename-prefixed.
// ==========================================================================
SHIFT_THRESH = 20;   // only shift if a row is at least this many px shorter than the previous
ZERO_EPS = 0;      // |value| <= this counts as background padding (0 = exact zero)
DO_BLUR  = true;   // apply your Gaussian blur to the display
// -------------------- 0. source folder + base name ------------------------
orig = getTitle();
dir  = getDirectory("image");                 // folder the movie was opened from
if (dir == "") dir = getDirectory("Choose a folder to save results");
base = orig;                                   // filename without extension
dotPos = lastIndexOf(base, ".");
if (dotPos > 0) base = substring(base, 0, dotPos);
name = getTitle();      // retrieve the name of the active image

// ... do other stuff that changes the active image ...

// -------------------- 1. raw kymograph from the plugin --------------------
run("LOI Interpolator", "average_over_line_width show_kymograph");
selectWindow("Kymograph of " + orig);
rename("Kymograph of Raw" + orig);
W = getWidth();
H = getHeight();
// -------------------- 2. per-row data length ------------------------------
L = newArray(H);
for (y = 0; y < H; y++) {
    len = 0;
    for (x = W - 1; x >= 0; x--) {
        if (abs(getPixel(x, y)) > ZERO_EPS) { len = x + 1; break; }
    }
    L[y] = len;
}
// -------------------- 3. cumulative right shift on shrinkage ---------------
offset = newArray(H);
acc = 0;
offset[0] = 0;
for (y = 1; y < H; y++) {
    if (L[y-1] - L[y] >= SHIFT_THRESH) acc += (L[y-1] - L[y]);   // shrank by >= threshold -> add the difference
    offset[y] = acc;                              // applies to this row and all after
}
// -------------------- 4. output width (no right restriction) --------------
Wout = 0;
for (y = 0; y < H; y++) {
    r = offset[y] + L[y];
    if (r > Wout) Wout = r;
}
// -------------------- 5. build the shifted image --------------------------
newImage("kymo_shifted"+ orig, "32-bit black", Wout, H, 1);
for (y = 0; y < H; y++) {
    selectWindow("Kymograph of Raw" + orig);
    row = newArray(L[y]);
    for (x = 0; x < L[y]; x++) row[x] = getPixel(x, y);
    selectWindow("kymo_shifted"+ orig);
    o = offset[y];
    for (x = 0; x < L[y]; x++) setPixel(o + x, y, row[x]);
}
// -------------------- 6. display ------------------------------------------
selectWindow("kymo_shifted"+ orig);
rename("Kymograph_Ant_Aligned of " + orig);
resetMinAndMax();
run("mpl-magma");
if (DO_BLUR) run("Gaussian Blur...", "sigma=1.5");
// -------------------- 7. save kymograph + ROIs ----------------------------
saveAs("Tiff", dir + base + "_Kymograph_LF_Aligned.tif");   // next to the source file
if (roiManager("count") > 0)
    roiManager("save", dir + base + "_RoiSet.zip");
else
    print("ROI Manager empty - no ROI file saved.");
// -------------------- 8. clean up -----------------------------------------
selectImage("Kymograph of Raw" + orig);
close();

selectWindow(name);     // bring that window back / make it active again
run("LOI Interpolator", "rois_are_flipped average_over_line_width show_kymograph");
run("mpl-magma");
run("Gaussian Blur...", "sigma=1.5");
saveAs("Tiff", dir + base + "_Kymograph_Pos_Aligned.tif");
