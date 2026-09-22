// ============================================================
//  Batch PSM plot-profile extraction
//  nd2 layout: 3 channels ->  ch1 = DAPI (mask), ch2 = venus, ch3 = ppERK
//  Antibody names are hardcoded (not parsed from filename)
//  Output goes into a folder named after the file (no antibody names)
// ============================================================

input = getDirectory("Input directory"); // Folder with the nd2 images to analyze
list = getFileList(input);
ll = list.length;
File.setDefaultDir(input);
for (i = 0; i < ll; i++) {
	open(list[i]);
}

for (im=1; im<ll+1; im++){
	input=getInfo("image.Directory");
	title=getTitle;
	extract=".nd2";

	// Remove the ".nd2" extension from the title
	subtitle = substring(title, 0, indexOf(title, extract));

	// --- Hardcoded antibody names ---
	abody1 = "venus";   // channel 2
	abody2 = "ppERK";   // channel 3

	// --- Output directory named only after the file (no antibody names) ---
	folder = input + subtitle + "/";
	if (!File.exists(folder)) {
		File.makeDirectory(folder);
	}

	run("Duplicate...", "title=NewStack.tif duplicate");
	Stack.getDimensions(width, height, channels, slices, frames);
	run("Despeckle");

	// ----- Mask from DAPI (channel 1) -----
	run("Duplicate...", "duplicate channels=1");
	getDimensions(width, height, channels, slices, frames);
	n = nSlices;
	for (s = 1; s <= n; s++) {
		setSlice(s);
		run("Enhance Local Contrast (CLAHE)", "blocksize=127 histogram=256 maximum=3 mask=*None* fast_(less_accurate) process_as_composite");
	}
	setOption("BlackBackground", true);
	run("Make Binary", "method=Default background=Dark calculate black");
	run("Erode", "stack");
	//run("Erode", "stack");
	//run("Erode", "stack");
	//run("Erode", "stack");
	run("16-bit");
	a=4095/255;
	run("Multiply...", "value=a stack");
	saveAs("Tiff", folder+"Mask.tif");

	// ----- abody1 = venus (channel 2) -----
	selectWindow("NewStack.tif");
	run("Duplicate...", "duplicate channels=2");
	saveAs("Tiff", folder+abody1+".tif");
	imageCalculator("Min create stack", abody1+".tif","Mask.tif");
	selectWindow("Result of "+abody1+".tif");
	saveAs("Tiff", folder+abody1+"_Masked.tif");

	// ----- abody2 = ppERK (channel 3) -----
	selectWindow("NewStack.tif");
	run("Duplicate...", "duplicate channels=3");
	saveAs("Tiff", folder+abody2+".tif");
	imageCalculator("Min create stack", abody2+".tif","Mask.tif");
	selectWindow("Result of "+abody2+".tif");
	saveAs("Tiff", folder+abody2+"_Masked.tif");

	// ----- Max projection of abody1 -----
	selectWindow(abody1+".tif");
	run("Z Project...", "projection=[Max Intensity]");
	saveAs("Tiff", folder+"MAX_"+abody1+".tif");

	selectWindow("NewStack.tif");
	close();

	selectWindow("MAX_"+abody1+".tif");
	run("Enhance Contrast", "saturated=0.35");
	selectWindow(abody2+".tif");
	run("Enhance Contrast", "saturated=0.35");

	a0=0;
	side=0;
	sides=1;

	while (side<sides) {
		for (j=1; j<slices+1; j++) {
			a=floor((j-3)/3)+1;

			if (j==1){
				setTool("polyline");
				beep();
				waitForUser("Select Line To Analyze, then click OK.");
				roiManager("Add");
				roiManager("Save", folder+".roi");
				selectWindow(abody2+".tif");
				setTool("polyline");
				roiManager("Select", 0);
				run("Plot Profile");
				selectWindow("Plot of ppERK");
				close();

			
			}

			// --- MAX abody1 profile ---
			selectWindow("MAX_"+abody1+".tif");
			setTool("polyline");
			roiManager("Select", 0);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder+"Values_"+abody1+"_"+toString(j)+toString(side)+".csv");

			// --- abody1 masked profile (per slice) ---
			selectWindow(abody1+"_Masked.tif");
			setTool("polyline");
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder+"Values_Masked"+abody1+"_"+toString(j)+toString(side)+".csv");

			// --- abody2 raw profile (per slice) ---
			selectWindow(abody2+".tif");
			setTool("polyline");
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder+"Values_"+abody2+"_"+toString(j)+toString(side)+".csv");

			// --- abody2 masked profile (per slice) ---
			selectWindow(abody2+"_Masked.tif");
			setTool("polyline");
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder+"Values_Masked"+abody2+"_"+toString(j)+toString(side)+".csv");

			// --- Mask profile (per slice) ---
			selectWindow("Mask.tif");
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder+"Values_Mask_"+toString(j)+toString(side)+".csv");

			roiManager("Save", folder+"PSM.roi");
			a0=floor((j-3)/3)+1;

			if(j==slices){
				roiManager("Delete");
			}
		}
		side=side+1;
	}

	// ----- cleanup -----
	selectWindow(title);
	close();
	selectWindow("Mask.tif");
	close();
	selectWindow(abody1+".tif");
	close();
	selectWindow(abody2+".tif");
	close();
	selectWindow(abody2+"_Masked.tif");
	close();
	selectWindow("MAX_"+abody1+".tif");
	close();
	selectWindow(abody1+"_Masked.tif");
	close();

	wlist = getList("window.titles");
	for (i=0; i<wlist.length; i++){
		window = wlist[i];
		selectWindow(window);
		run("Close");
	}
}
