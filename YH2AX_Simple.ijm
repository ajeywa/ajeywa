// YH2AX foci analysis - simple version. No files are written.
// You pick ch00, set the nuclear threshold, pick ch02, set the YH2AX threshold.
// Output: "Results" window (one row per focus) + "YH2AX_Summary" window + Log.

macro "YH2AX Simple" {

    // ----- ch00: nuclear mask -----
    ch00Path = File.openDialog("Select the ch00 nuclear stack");
    if (ch00Path == "")
        exit("No ch00 image selected.");
    open(ch00Path);
    if (nSlices > 1)
        run("Z Project...", "projection=[Sum Slices]");

    run("Threshold...");
    waitForUser("Set the NUCLEAR threshold, then click OK here (do not click Apply).");
    getThreshold(nucLower, nucUpper);
    if (nucLower == -1)
        exit("No nuclear threshold was set.");

    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Dilate");
    run("Fill Holes");
    nuclearMask = getTitle();
    run("Divide...", "value=255");      // mask becomes 0/1
    setMinAndMax(0, 1);

    // ----- ch02: keep only what is inside nuclei -----
    yh2axPath = File.openDialog("Select the ch02 / YH2AX stack");
    if (yh2axPath == "")
        exit("No ch02/YH2AX image selected.");
    open(yh2axPath);
    yh2axStack = getTitle();
    imageName = File.getName(yh2axPath);
    n = nSlices;

    imageCalculator("Multiply create stack", yh2axStack, nuclearMask);
    maskedStack = getTitle();

    run("Threshold...");
    waitForUser("Set the YH2AX threshold, then click OK here (do not click Apply).");
    getThreshold(fociLower, fociUpper);
    if (fociLower == -1)
        exit("No YH2AX threshold was set.");

    // ----- make a binary copy and measure every focus on every slice -----
    run("Duplicate...", "title=YH2AX_binary duplicate");
    setThreshold(fociLower, fociUpper);
    setOption("BlackBackground", true);
    run("Convert to Mask", "method=Default background=Dark black");

    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");
    run("Clear Results");
    run("Analyze Particles...", "size=0.01-Infinity display clear stack");

    // ----- averages over the stack -----
    total = nResults;
    sumArea = 0;
    for (k = 0; k < total; k++)
        sumArea += getResult("Area", k);
    meanCount = total / n;
    meanArea  = sumArea / n;

    Table.create("YH2AX_Summary");
    Table.set("Image", 0, imageName);
    Table.set("Nuclear threshold lower", 0, nucLower);
    Table.set("Nuclear threshold upper", 0, nucUpper);
    Table.set("YH2AX threshold lower", 0, fociLower);
    Table.set("YH2AX threshold upper", 0, fociUpper);
    Table.set("Slices analysed", 0, n);
    Table.set("Mean foci count per slice", 0, meanCount);
    Table.set("Mean foci area per slice", 0, meanArea);
    Table.update("YH2AX_Summary");

    print("Image\tNuclear threshold lower\tNuclear threshold upper\tYH2AX threshold lower\tYH2AX threshold upper\tSlices analysed\tMean foci count per slice\tMean foci area per slice");
    print(imageName + "\t" + nucLower + "\t" + nucUpper + "\t" + fociLower + "\t"
          + fociUpper + "\t" + n + "\t" + meanCount + "\t" + meanArea);
    print("DONE: " + total + " foci in " + n + " slices.");
}
