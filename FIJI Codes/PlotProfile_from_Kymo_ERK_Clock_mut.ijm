// ==========================================
// FIJI Macro: Kymograph Plot Profiles (NUMERIC SORT FIX + GAUSSIAN BLUR + SAVE BLURRED)
// ==========================================

// Select folder
dir = getDirectory("Choose folder containing Kymograph TIFF images");
if (dir == "") exit("No folder selected.");

// Select ROI
roiPath = File.openDialog("Choose ROI file (.roi)");
if (roiPath == "") exit("No ROI selected.");

// Blur setting
blurSigma = 1.5;

// Output folder for blurred kymographs
blurDir = dir + "Gaussian_Blurred" + File.separator;
if (!File.exists(blurDir))
    File.makeDirectory(blurDir);

// Get file list
fileList = getFileList(dir);

// Filter Kymograph files
validFiles = newArray();
numList = newArray();
for (i = 0; i < fileList.length; i++) {
    name = fileList[i];
    if ((endsWith(name, ".tif") || endsWith(name, ".tiff")) &&
        indexOf(name, "Kymograph") != -1) {
        validFiles = Array.concat(validFiles, name);
        // extract first number in filename for sorting
        num = extractNumber(name);
        numList = Array.concat(numList, num);
    }
}

// ==========================================
// NUMERIC SORT (bubble sort simple & robust)
// ==========================================
for (i = 0; i < validFiles.length - 1; i++) {
    for (j = i + 1; j < validFiles.length; j++) {
        if (numList[j] < numList[i]) {
            // swap numbers
            tempN = numList[i];
            numList[i] = numList[j];
            numList[j] = tempN;
            // swap filenames
            tempF = validFiles[i];
            validFiles[i] = validFiles[j];
            validFiles[j] = tempF;
        }
    }
}

count = validFiles.length;
if (count == 0) exit("No Kymograph files found.");

// ==========================================
// First pass: blur, save blurred copy, get max profile length
// ==========================================
maxLen = 0;
setBatchMode(true);
for (i = 0; i < count; i++) {
    open(dir + validFiles[i]);
    run("Gaussian Blur...", "sigma=" + blurSigma);   // <-- blur before profile

    // save blurred copy into subfolder
    saveAs("Tiff", blurDir + "Blurred_" + validFiles[i]);

    roiManager("Reset");
    roiManager("Open", roiPath);
    roiManager("Select", 0);
    profile = getProfile();
    if (profile.length > maxLen)
        maxLen = profile.length;
    close();
}

// ==========================================
// Storage
// ==========================================
table = newArray(maxLen);
for (r = 0; r < maxLen; r++)
    table[r] = "";

// ==========================================
// Extract profiles
// ==========================================
for (i = 0; i < count; i++) {
    open(dir + validFiles[i]);
    run("Gaussian Blur...", "sigma=" + blurSigma);   // <-- blur before profile
    roiManager("Reset");
    roiManager("Open", roiPath);
    roiManager("Select", 0);
    profile = getProfile();
    for (r = 0; r < maxLen; r++) {
        if (r < profile.length)
            value = "" + profile[r];
        else
            value = "";
        if (i == 0)
            table[r] = value;
        else
            table[r] = table[r] + "," + value;
    }
    close();
}
setBatchMode(false);

// ==========================================
// CSV
// ==========================================
csv = "";
for (i = 0; i < count; i++) {
    csv += "Embryo_" + (i + 1);
    if (i < count - 1)
        csv += ",";
}
csv += "\n";

for (r = 0; r < maxLen; r++)
    csv += table[r] + "\n";

// ==========================================
// Save in same folder
// ==========================================
savePath = dir + "Clock_PlotProfiles.csv";
File.saveString(csv, savePath);

print("Done!");
print("Saved profiles: " + savePath);
print("Saved blurred kymographs: " + blurDir);

// ==========================================
// Helper: extract first number from filename
// ==========================================
function extractNumber(name) {
    num = "";
    for (k = 0; k < lengthOf(name); k++) {
        c = substring(name, k, k+1);
        if (c >= "0" && c <= "9")
            num = num + c;
        else if (num != "")
            break;
    }
    if (num == "")
        return 0;
    return parseInt(num);
}