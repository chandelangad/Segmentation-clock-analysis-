input = getDirectory("Input directory"); // Select the folder including nd2 images of the data to be analyzed
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

    // Split the filename into parts using "_"
    parts = split(subtitle, "_");

    // Ensure there are enough parts
    if (parts.length < 4) {
        print("Error: Filename does not contain enough parts separated by '_'. Skipping file: " + title);
        continue; // Skip this iteration if the filename is malformed
    }

    // Assign antibodies to variables
    abody1 = parts[1]; // First antibody
    abody2 = parts[2]; // Second antibody
    abody3 = parts[3]; // Third antibody

    // Create directories
    folder = input + subtitle + "/";
    folder1 = folder + abody1 + "_" + abody2 + "_" + abody3 + "/";
   // folder2 = folder + abody2 + "/";

    if (!File.exists(folder)) {
        File.makeDirectory(folder);
    }
    if (!File.exists(folder1)) {
        File.makeDirectory(folder1);
    }
  

 

run("Duplicate...", "title=NewStack.tif duplicate"); 
Stack.getDimensions(width, height, channels, slices, frames); 
run("Despeckle");
run("Duplicate...", "duplicate channels=1");
setOption("BlackBackground", true);
run("Make Binary", "method=Default background=Dark calculate black");
run("Erode", "stack");
run("Erode", "stack");
run("Erode", "stack");
run("16-bit");
a=4095/255;
run("Multiply...", "value=a stack");
saveAs("Tiff", folder1+"Mask.tif");
//saveAs("Tiff", folder2+"Mask.tif");

selectWindow("NewStack.tif"); 
run("Duplicate...", "duplicate channels=2");
saveAs("Tiff", folder1+abody1+".tif");


selectWindow("NewStack.tif"); 
run("Duplicate...", "duplicate channels=2");
//run("Remove Outliers...", "radius=2 threshold=50 which=Bright stack");
saveAs("Tiff", folder1+abody1+".tif");
imageCalculator("Min create stack", abody1+".tif","Mask.tif");
selectWindow("Result of "+abody1+".tif");
saveAs("Tiff", folder1+abody1+"_Masked.tif");

selectWindow("NewStack.tif"); 
run("Duplicate...", "duplicate channels=3");
//run("Remove Outliers...", "radius=2 threshold=50 which=Bright stack");
saveAs("Tiff", folder1+abody2+".tif");
imageCalculator("Min create stack", abody2+".tif","Mask.tif");
selectWindow("Result of "+abody2+".tif");
saveAs("Tiff", folder1+abody2+"_Masked.tif");

selectWindow("NewStack.tif"); 
run("Duplicate...", "duplicate channels=4");
saveAs("Tiff", folder1+abody3+".tif");
imageCalculator("Min create stack", abody3+".tif","Mask.tif");
selectWindow("Result of "+abody3+".tif");
saveAs("Tiff", folder1+abody3+"_Masked.tif");

selectWindow(abody1+".tif");	
run("Z Project...", "projection=[Max Intensity]");
saveAs("Tiff", folder1+"MAX_"+abody1+".tif");



//selectWindow("NewStack.tif"); 
//run("Duplicate...", "duplicate channels=2");
//saveAs("Tiff", folder1+"GFP.tif");
//saveAs("Tiff", folder2+"GFP.tif");
//imageCalculator("Min create stack", "GFP.tif","Mask.tif");
//selectWindow("Result of GFP.tif");
//saveAs("Tiff", folder1+"GFP_Masked.tif");
//saveAs("Tiff", folder2+"GFP_Masked.tif");


			
selectWindow("NewStack.tif"); 
close();
selectWindow("MAX_"+abody1+".tif");
run("Enhance Contrast", "saturated=0.35");
selectWindow(abody3+"_Masked.tif");	
run("Enhance Contrast", "saturated=0.35");
selectWindow(abody2+".tif");
run("Enhance Contrast", "saturated=0.35");


a0=0;
side=0;

  Dialog.create("How is that sample mounted?");
  Dialog.addChoice("Mounting:", newArray("Lateral","Flat","Skip"));
  beep();  
  Dialog.show();
  mount = Dialog.getChoice();
  if (mount=="Flat") {
  sides=2;
  }
  if (mount=="Lateral") {
  sides=1;
  }
  if (mount=="Skip") {
  sides=0;
  }

 
  while (side<sides) {
for (j=1; j<slices+1; j++) { 
	a=floor((j-3)/3)+1;	
	if (j==1){
		
		setTool("polyline"); 
		beep();  
				waitForUser("Select Line To Analyze, then click OK.");
		roiManager("Add");
		roiManager("Save", folder1+".roi");
		selectWindow(abody2+".tif");
		setTool("polyline");  
		roiManager("Select", 0);
		run("Plot Profile");
		
		selectWindow("MAX_"+abody1+".tif");
		setTool("polyline");  
		roiManager("Select", 0);
		run("Plot Profile");
		selectWindow("Plot of ppERK");
		waitForUser("If ready, then click OK.");
		selectWindow("Plot of ppERK");
		close();
		selectWindow("Plot of MAX_Her7Venus");
		close();
		}

			selectWindow("MAX_"+abody1+".tif");
			//run("Z Project...", "projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			//setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_"+abody1+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody1+".tif"); 
			//close();
			
			selectWindow(abody1+"_Masked.tif");	
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_Masked"+abody2+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();
			

			selectWindow(abody2+"_Masked.tif");	
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_Masked"+abody2+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();

			selectWindow(abody2+".tif");
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_"+abody2+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();
			
			selectWindow(abody3+"_Masked.tif");	
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_Masked"+abody3+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();
			
			selectWindow(abody3+".tif");	
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_"+abody3+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();

			selectWindow(abody1+"_Masked.tif");	
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			setTool("polyline");  
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_Masked"+abody1+"_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_"+abody+"_Masked.tif"); 
			//close();
			
			
			selectWindow("Mask.tif"); 
			//run("Z Project...", "start=&str stop=&stp projection=[Max Intensity]");
			//selectWindow("MAX_Mask.tif"); 
			roiManager("Select", 0);
			setSlice(j);
			run("Clear Results");
			profile = getProfile();
			for (i=0; i<profile.length; i++)
				setResult("Value", i, profile[i]);
			updateResults();
			saveAs("Measurements", folder1+"Values_Mask_"+toString(j)+toString(side)+".csv");
			//saveAs("Measurements", folder2+"Values_Mask_"+toString(j)+toString(side)+".csv");
			//selectWindow("MAX_Mask.tif"); 
			//close();
			
	roiManager("Save", folder1+"PSM.roi");
	a0=floor((j-3)/3)+1;
	
	if(j==slices){
		roiManager("Delete");
		
	}
	}
	side=side+1;
}
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
	selectWindow(abody3+".tif");
	close();
	selectWindow(abody3+"_Masked.tif");
	close();
	selectWindow("MAX_"+abody1+".tif"); 
	close();
	selectWindow(abody1+"_Masked.tif");	
	close();
	selectWindow(abody1+".tif");
	close();


			//saveAs("Measurements", folder1+"Values_"+abody1+"_"+toString(100)+".csv");
			//saveAs("Measurements", folder1+"Values_"+abody1+"_"+toString(110)+".csv");
	
	
	//selectWindow("GFP.tif");
	//close();
	//selectWindow("GFP_Masked.tif");
	//close();
	
wlist = getList("window.titles"); 
for (i=0; i<wlist.length; i++){      
	window = wlist[i]; 
	selectWindow(window); 
	run("Close"); 
	} 
	} 