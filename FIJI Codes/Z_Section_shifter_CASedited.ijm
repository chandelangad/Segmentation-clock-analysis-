
Stack.getDimensions(width, height, channels, slices, frames);
Dialog.create("How many shift jumps do you have in the movie?");

  //Dialog.addNumber("total shifts:", 5);
  Dialog.addNumber("total shifts:",6);
  beep();  
  Dialog.show();
  numsh=Dialog.getNumber();
  Dialog.addNumber("No. of channels",7);
  beep();  
  Dialog.show();
  numchan=Dialog.getNumber();

  framearray=newArray(numsh);
  z1array=newArray(numsh);
  z2array=newArray(numsh);
for (i = 0; i < numsh; i++) {	
	dial="Shift #"+toString(i+1)+":";
	Dialog.create(dial);
	Dialog.addNumber("frame of shift:", 1);
	Dialog.addNumber("z before shift:", 1);
	Dialog.addNumber("z after shift:", 1);
	beep();
	Dialog.show();
	framearray[i]=Dialog.getNumber();
	z1array[i]=Dialog.getNumber();
	z2array[i]=Dialog.getNumber();
}

framearray=Array.concat(0,framearray,frames);

shiftedarray=newArray(numsh+1);
shiftedarray[0]=0;
shiftedarray[numsh]=0;
for (shift = 0; shift < numsh; shift++) {
	shifted=shift;
  while (shifted<numsh) {
  	shiftedarray[shift]=shiftedarray[shift]+z1array[shifted]-z2array[shifted];
  	shifted=shifted+1;
  }
}

//shiftedarray=newArray(22, 27, 23, 20, 14, 9, 11, 5, 2, -1, -5, 0);
Array.getStatistics(shiftedarray, minsh, maxsh, meansh, stdDevsh);
//shiftedarray=Array.concat(shiftedarray,0);
adds=maxsh-minsh;
//Array.print(framearray);
//Array.print(z1array);
//Array.print(z2array);
//Array.print(shiftedarray);


//create extra slices

for (i = 0; i < adds; i++) {
	run("Add Slice", "add=slice prepend");
}


//z-layer shifts

for (sh=0; sh < numsh+1; sh++) {
	for (i = framearray[sh]+1; i < framearray[sh+1]+1; i++) {
	Stack.setFrame(i);
	startz=maxsh-shiftedarray[sh];
	for (n = 1; n < slices+1; n++) {
		for (c = 1;c< numchan+7; c++) {
			Stack.setSlice(n+adds);
			Stack.setChannel(c);
			run("Select All");
			run("Copy");
			Stack.setSlice(startz+n);
			run("Paste");
		}		
		}
		for (n = startz+slices; n < adds+slices; n++) {
			for (c = 1;c< numchan+7; c++) {
				Stack.setChannel(c);
				Stack.setSlice(n+1);
				run("Select All");
				setBackgroundColor(0, 0, 0);
				run("Clear", "slice");
			}
		}
}
}
