// YH2AX foci analysis - INTENSITY thresholding: foci are pixels between intensityLower and intensityUpper; no upper size limit.
// No files are written. You pick ch00 and ch02. Nuclear threshold = automatic Otsu.
// Output: "Results" window (one row per focus) + "YH2AX_Summary" window + Log.
//
// ---- SETTINGS: edit these numbers, then Run ----
// Area filter for foci, in the image's calibrated units (um^2 if the image has a scale, pixels if not).
// areaMax = 0 means no upper limit.
var areaMin = 0.01;
var areaMax = 0;
// YH2AX intensity threshold. intensityUpper = 0 means the maximum value for the image type.
var intensityLower = 40;
var intensityUpper = 0;

macro "YH2AX Intensity Threshold" {

    // ----- ch00: nuclear mask -----
    ch00Path = File.openDialog("Select the ch00 nuclear stack");
    if (ch00Path == "")
        exit("No ch00 image selected.");
    open(ch00Path);
    if (nSlices > 1)
        run("Z Project...", "projection=[Sum Slices]");

    // Nuclear channel: automatic Otsu threshold on the Z-projected (SUM) image
    setAutoThreshold("Otsu dark");
    getThreshold(nucLower, nucUpper);
    print(getTitle() + "  nuclear lower = " + nucLower);

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

    // YH2AX intensity threshold from the SETTINGS at the top
    selectWindow(maskedStack);
    fociLower = intensityLower;
    bd = bitDepth();
    if (intensityUpper > 0)
        fociUpper = intensityUpper;
    else if (bd == 32)
        fociUpper = 1e30;
    else
        fociUpper = pow(2, bd) - 1;

    // ----- make a binary copy and measure every focus on every slice -----
    run("Duplicate...", "title=YH2AX_binary duplicate");
    setThreshold(fociLower, fociUpper);
    setOption("BlackBackground", true);
    run("Convert to Mask", "method=Default background=Dark black");

    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");
    run("Clear Results");
    areaMaxText = "Infinity";
    if (areaMax > 0)
        areaMaxText = "" + areaMax;
    run("Analyze Particles...", "size=" + areaMin + "-" + areaMaxText + " display clear stack");

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
    Table.set("Foci area min", 0, areaMin);
    Table.set("Foci area max", 0, areaMax);
    Table.set("Slices analysed", 0, n);
    Table.set("Mean foci count per slice", 0, meanCount);
    Table.set("Mean foci area per slice", 0, meanArea);
    Table.update("YH2AX_Summary");

    print("Image\tNuclear threshold lower\tNuclear threshold upper\tYH2AX threshold lower\tYH2AX threshold upper\tFoci area min\tFoci area max\tSlices analysed\tMean foci count per slice\tMean foci area per slice");
    print(imageName + "\t" + nucLower + "\t" + nucUpper + "\t" + fociLower + "\t"
          + fociUpper + "\t" + areaMin + "\t" + areaMax + "\t" + n + "\t" + meanCount + "\t" + meanArea);
    print("DONE: " + total + " foci in " + n + " slices.");
}
