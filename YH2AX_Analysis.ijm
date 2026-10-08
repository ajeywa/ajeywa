macro "YH2AX Analysis" {

    // ---------- 1–3: Open ch00 and Z-project ----------
    ch00Path = File.openDialog("Select the ch00 nuclear stack");
    if (ch00Path == "")
        exit("No ch00 image selected.");

    open(ch00Path);
    if (nSlices > 1)
        run("Z Project...", "projection=[Sum Slices]");

    // ---------- 4: MANUAL nuclear threshold (recorded) ----------
    run("Threshold...");
    waitForUser("Set the nuclear threshold, then click OK here.");
    getThreshold(nucLower, nucUpper);
    if (nucLower == -1)
        exit("No nuclear threshold was set.");

    // ---------- 5–6: Binary + nuclear mask ----------
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Dilate");
    run("Fill Holes");
    nuclearMask = getTitle();

    // 0/255 -> 0/1 so it can be multiplied (avoids 16-bit AND truncation)
    run("Divide...", "value=255");
    setMinAndMax(0, 1);

    // ---------- 7–8: Open YH2AX stack ----------
    yh2axPath = File.openDialog("Select the ch02 / YH2AX stack");
    if (yh2axPath == "")
        exit("No ch02/YH2AX image selected.");

    open(yh2axPath);
    yh2axStack = getTitle();
    imageName = File.getName(yh2axPath);

    // ---------- Check XY dimensions ----------
    getDimensions(yWidth, yHeight, yChannels, ySlices, yFrames);
    selectWindow(nuclearMask);
    getDimensions(width, height, channels, slices, frames);
    if (width != yWidth || height != yHeight)
        exit("The nuclear mask and YH2AX stack do not have matching XY dimensions.");

    // ---------- 9: Mask the YH2AX stack ----------
    imageCalculator("Multiply create stack", yh2axStack, nuclearMask);
    maskedYH2AX = getTitle();

    // ---------- 10: MANUAL YH2AX threshold (recorded) ----------
    selectWindow(maskedYH2AX);
    run("Threshold...");
    waitForUser("Set the YH2AX threshold, then click OK here.");
    getThreshold(fociLower, fociUpper);
    if (fociLower == -1)
        exit("No YH2AX threshold was set.");

    // Binary copy for particle detection; the intensity stack stays untouched
    run("Duplicate...", "title=YH2AX_binary duplicate");
    binaryStack = getTitle();
    setThreshold(fociLower, fociUpper);
    setOption("BlackBackground", true);
    run("Convert to Mask", "method=Default background=Dark black");

    // ---------- 11: Measure each focus, slice by slice ----------
    // Area/Mean/Min/Max/IntDen/RawIntDen are measured on the raw YH2AX
    // intensities (redirect), not on the binary image.
    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");

    fociCsv = File.getDirectory(yh2axPath) + "YH2AX_foci.csv";
    if (!File.exists(fociCsv))
        File.append("Image,Slice,Foci No.,Area,Mean,Min,Max,IntDen,RawIntDen", fociCsv);

    // On-screen table with the same per-focus rows (select all, copy, paste into Excel)
    Table.create("YH2AX_Foci");

    n = nSlices;
    sumCount = 0;
    sumArea = 0;

    for (i = 1; i <= n; i++) {
        selectWindow(binaryStack);
        setSlice(i);
        run("Analyze Particles...", "size=0.01-Infinity display clear");

        sliceCount = nResults;
        sliceArea = 0;
        for (r = 0; r < sliceCount; r++) {
            a = getResult("Area", r);
            sliceArea += a;

            row = Table.size("YH2AX_Foci");
            Table.set("Image", row, imageName, "YH2AX_Foci");
            Table.set("Slice", row, i, "YH2AX_Foci");
            Table.set("Foci No.", row, r + 1, "YH2AX_Foci");
            Table.set("Area", row, a, "YH2AX_Foci");
            Table.set("Mean", row, getResult("Mean", r), "YH2AX_Foci");
            Table.set("Min", row, getResult("Min", r), "YH2AX_Foci");
            Table.set("Max", row, getResult("Max", r), "YH2AX_Foci");
            Table.set("IntDen", row, getResult("IntDen", r), "YH2AX_Foci");
            Table.set("RawIntDen", row, getResult("RawIntDen", r), "YH2AX_Foci");

            File.append(imageName + "," + i + "," + (r + 1) + "," + a + ","
                        + getResult("Mean", r) + "," + getResult("Min", r) + ","
                        + getResult("Max", r) + "," + getResult("IntDen", r) + ","
                        + getResult("RawIntDen", r), fociCsv);
        }

        sumCount += sliceCount;
        sumArea += sliceArea;
    }

    Table.update("YH2AX_Foci");

    // Results window only holds the last slice; close it to avoid confusion
    if (isOpen("Results")) {
        selectWindow("Results");
        run("Close");
    }

    // Divide by however many slices were analysed
    meanCount = sumCount / n;
    meanArea  = sumArea  / n;

    // ---------- Summary table ----------
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

    // ---------- Append to a running CSV (one row per image) ----------
    csvPath = File.getDirectory(yh2axPath) + "YH2AX_results.csv";
    if (!File.exists(csvPath))
        File.append("Image,NucLower,NucUpper,YH2AXLower,YH2AXUpper,Slices,MeanFociCount,MeanFociArea", csvPath);
    File.append(imageName + "," + nucLower + "," + nucUpper + ","
                + fociLower + "," + fociUpper + "," + n + ","
                + meanCount + "," + meanArea, csvPath);

    print("Per-image summary: " + csvPath);
    print("Per-focus data: " + fociCsv);
    print("Slices analysed: " + n);
    print("YH2AX threshold: " + fociLower + " - " + fociUpper);
    print("Mean foci count per slice: " + meanCount);
    print("Mean foci area per slice: " + meanArea);
}
