input = getDirectory("Input directory"); 
run("Image Sequence...", "dir=["+input+"] sort");
rename("sfc");
run("Split Channels");
imageCalculator("Subtract create stack", "sfc (red)","sfc (blue)");

selectWindow("sfc (green)"); 
getDimensions(width, height, channels, slices, frames);


run("Z Project...", "projection=[Average Intensity]");
run("Enhance Contrast", "saturated=0.35");
setTool(8);
waitForUser("Pick a territory shared in all frames and click OK!");
Roi.getCoordinates(xc, yc);
close();

selectWindow("sfc (green)");  
run("Duplicate...", "title=ERK_tissuemask duplicate");
for (i = 1; i <= nSlices; i++) {
    setSlice(i);
    doWand(xc[0], yc[0]);
    setForegroundColor(255, 255, 255);
    run("Fill", "slice");
    run("Clear Outside", "slice");
}

imageCalculator("Min create stack", "Result of sfc (red)","ERK_tissuemask");
selectWindow("Result of Result of sfc (red)");
run("Median...", "radius=5 stack");

saveAs("Tiff", input+"ERK_noedge.tif");
//selectWindow("sfc (blue)");
//close();
selectWindow("sfc (red)");
close();
selectWindow("ERK_tissuemask");
saveAs("Tiff", input+"ERK_tissuemask.tif");
selectImage("sfc (blue)");
doWand(1228, 500);
selectImage("ERK_noedge.tif");
run("Restore Selection");
run("Duplicate...", "duplicate");
selectImage("ERK_noedge-1.tif");
run("Flip Vertically", "stack");