text1 = "ERK Activity"; 
//text2 = "psMEK"; // replace with your actual text
x1 = 10;                    // x position
y1 = 50;     // y position
//x2 = 1046

setFont("SansSerif", 40, "bold");
setColor("white");         // match whatever color you used

n = nSlices;
for (i = 1; i <= n; i++) {
    setSlice(i);
    drawString(text1, x1, y1);
   // drawString(text2, x2, y1);
}

updateDisplay();
run("RGB Color");