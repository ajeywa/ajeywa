// YH2AX foci analysis - INTENSITY thresholding.
// Foci are detected, then each focus is kept or dropped by how bright it is in channel 2
// (its own measured pixel values), e.g. keep only foci with Mean intensity >= intensityMin.
// No files are written. You pick ch00 and ch02. Nuclear threshold = automatic Otsu.
// Output: "Results" window (kept foci only) + "YH2AX_Summary" window + Log.
//
// ---- SETTINGS: edit these numbers, then Run ----
// Pixel intensity used to DETECT foci in channel 2. detectUpper = 0 means the maximum for the image type.
var detectLower = 40;
var detectUpper = 0;
// Size limit for detection (calibrated units; um^2 if the image has a scale, pixels if not).
var areaMin = 0.01;
// Which brightness measurement of each focus to filter on:
//   "Mean" (average pixel value), "Max" (brightest pixel), "IntDen" or "RawIntDen" (total signal)
var intensityStat = "Mean";
// Keep foci whose value is >= intensityMin and <= intensityMax. intensityMax = 0 means no upper limit.
var intensityMin = 0;
var intensityMax = 0;

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

    // Foci detection threshold from the SETTINGS at the top
    selectWindow(maskedStack);
    fociLower = detectLower;
    bd = bitDepth();
    if (detectUpper > 0)
        fociUpper = detectUpper;
    else if (bd == 32)
        fociUpper = 1e30;
    else
        fociUpper = pow(2, bd) - 1;

    if (intensityStat != "Mean" && intensityStat != "Max" && intensityStat != "IntDen" && intensityStat != "RawIntDen")
        exit("intensityStat must be \"Mean\", \"Max\", \"IntDen\" or \"RawIntDen\".");

    // ----- make a binary copy and measure every focus on every slice -----
    run("Duplicate...", "title=YH2AX_binary duplicate");
    setThreshold(fociLower, fociUpper);
    setOption("BlackBackground", true);
    run("Convert to Mask", "method=Default background=Dark black");

    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");
    run("Clear Results");
    run("Analyze Particles...", "size=" + areaMin + "-Infinity display clear stack");

    // ----- keep only foci that pass the intensity filter -----
    detected = nResults;
    aArea = newArray(detected);  aMean = newArray(detected);  aMin = newArray(detected);
    aMax  = newArray(detected);  aInt  = newArray(detected);  aRaw = newArray(detected);
    kept = 0;
    sumArea = 0;
    for (k = 0; k < detected; k++) {
        v = getResult(intensityStat, k);
        if (v >= intensityMin && (intensityMax == 0 || v <= intensityMax)) {
            aArea[kept] = getResult("Area", k);
            aMean[kept] = getResult("Mean", k);
            aMin[kept]  = getResult("Min", k);
            aMax[kept]  = getResult("Max", k);
            aInt[kept]  = getResult("IntDen", k);
            aRaw[kept]  = getResult("RawIntDen", k);
            sumArea += aArea[kept];
            kept++;
        }
    }
    run("Clear Results");
    for (k = 0; k < kept; k++) {
        setResult("Area", k, aArea[k]);
        setResult("Mean", k, aMean[k]);
        setResult("Min", k, aMin[k]);
        setResult("Max", k, aMax[k]);
        setResult("IntDen", k, aInt[k]);
        setResult("RawIntDen", k, aRaw[k]);
    }
    updateResults();

    // ----- averages over the stack (kept foci only) -----
    total = kept;
    meanCount = total / n;
    meanArea  = sumArea / n;

    Table.create("YH2AX_Summary");
    Table.set("Image", 0, imageName);
    Table.set("Nuclear threshold lower", 0, nucLower);
    Table.set("Nuclear threshold upper", 0, nucUpper);
    Table.set("YH2AX threshold lower", 0, fociLower);
    Table.set("YH2AX threshold upper", 0, fociUpper);
    Table.set("Foci intensity statistic", 0, intensityStat);
    Table.set("Foci intensity min", 0, intensityMin);
    Table.set("Foci intensity max", 0, intensityMax);
    Table.set("Foci detected before filter", 0, detected);
    Table.set("Slices analysed", 0, n);
    Table.set("Mean foci count per slice", 0, meanCount);
    Table.set("Mean foci area per slice", 0, meanArea);
    Table.update("YH2AX_Summary");

    print("Image\tNuclear threshold lower\tNuclear threshold upper\tYH2AX threshold lower\tYH2AX threshold upper\tFoci intensity statistic\tFoci intensity min\tFoci intensity max\tFoci detected before filter\tSlices analysed\tMean foci count per slice\tMean foci area per slice");
    print(imageName + "\t" + nucLower + "\t" + nucUpper + "\t" + fociLower + "\t"
          + fociUpper + "\t" + intensityStat + "\t" + intensityMin + "\t" + intensityMax + "\t" + detected + "\t" + n + "\t" + meanCount + "\t" + meanArea);
    print("DONE: kept " + total + " of " + detected + " foci in " + n + " slices.");
}
