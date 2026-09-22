macro "Kymograph Plot Profile Exporter" {

    imgDir = getDirectory("Choose folder containing Kymograph TIFF images");
    if (imgDir == "") exit("No folder selected.");

    roiPath = File.openDialog("Choose ROI file (.roi)");
    if (roiPath == "") exit("No ROI selected.");

    blurDir = imgDir + "Blurred_Kymographs/";
    if (!File.exists(blurDir)) File.makeDirectory(blurDir);

    allFiles = getFileList(imgDir);
    total = lengthOf(allFiles);

    imgCount = 0;
    for (i = 0; i < total; i++) {
        nameLow = toLowerCase(allFiles[i]);
        hasKymo = indexOf(nameLow, "kymograph");
        hasTif = endsWith(nameLow, ".tif");
        if (hasKymo > -1 && hasTif) {
            imgCount = imgCount + 1;
        }
    }

    if (imgCount < 1) exit("No Kymograph .tif files found.");

    kymFiles = newArray(imgCount);
    idx = 0;
    for (i = 0; i < total; i++) {
        nameLow = toLowerCase(allFiles[i]);
        hasKymo = indexOf(nameLow, "kymograph");
        hasTif = endsWith(nameLow, ".tif");
        if (hasKymo > -1 && hasTif) {
            kymFiles[idx] = allFiles[i];
            idx = idx + 1;
        }
    }

    kymFiles = Array.sort(kymFiles);

    profileStrings = newArray(imgCount);
    profileLengths = newArray(imgCount);
    maxLen = 0;

    for (i = 0; i < imgCount; i++) {
        open(imgDir + kymFiles[i]);

        //run("Gaussian Blur...", "sigma=1");

        fname = kymFiles[i];
        stemName = substring(fname, 0, lengthOf(fname) - 4);
        saveAs("Tiff", blurDir + stemName + "_blur1.tif");

        roiManager("reset");
        roiManager("open", roiPath);
        roiManager("select", 0);
        profile = getProfile();
        pLen = lengthOf(profile);
        profileLengths[i] = pLen;
        if (pLen > maxLen) maxLen = pLen;
        s = "";
        for (j = 0; j < pLen; j++) {
            if (j > 0) s = s + ",";
            s = s + d2s(profile[j], 4);
        }
        profileStrings[i] = s;
        close();
        print("Done - " + kymFiles[i]);
    }

    headerRow = "";
    for (i = 0; i < imgCount; i++) {
        fname = kymFiles[i];
        colName = substring(fname, 0, lengthOf(fname) - 4);
        if (i > 0) headerRow = headerRow + ",";
        headerRow = headerRow + colName;
    }

    csvContent = headerRow + "\n";
    for (r = 0; r < maxLen; r++) {
        line = "";
        for (i = 0; i < imgCount; i++) {
            if (i > 0) line = line + ",";
            if (r < profileLengths[i]) {
                parts = split(profileStrings[i], ",");
                line = line + parts[r];
            }
        }
        csvContent = csvContent + line + "\n";
    }

    savePath = imgDir + "Kymograph_PlotProfiles.csv";
    File.saveString(csvContent, savePath);
    showMessage("Done", "Saved to\n" + savePath);
}
