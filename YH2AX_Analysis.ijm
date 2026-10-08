macro "YH2AX Analysis" {

    print("[1] Macro started");

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

    print("[2] Nuclear mask built. Nuclear threshold: " + nucLower + " - " + nucUpper);

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
    print("[3] YH2AX stack opened and masked: " + maskedYH2AX);

    // ---------- 10: MANUAL YH2AX threshold (recorded) ----------
    selectWindow(maskedYH2AX);
    run("Threshold...");
    waitForUser("Set the YH2AX threshold, then click OK here.");
    print("[4] OK clicked on YH2AX threshold. Active image: " + getTitle());
    getThreshold(fociLower, fociUpper);
    print("[5] YH2AX threshold read: " + fociLower + " - " + fociUpper);
    if (fociLower == -1)
        exit("No YH2AX threshold was set. Set it and leave the Threshold window on 'Set'/'Auto' (do NOT click Apply).");

    // Binary copy for particle detection; the intensity stack stays untouched
    run("Duplicate...", "title=YH2AX_binary duplicate");
    binaryStack = getTitle();
    setThreshold(fociLower, fociUpper);
    setOption("BlackBackground", true);
    run("Convert to Mask", "method=Default background=Dark black");
    print("[6] Binary stack created: " + binaryStack + " (" + nSlices + " slices)");

    // ---------- 11: Measure each focus, slice by slice ----------
    // Area/Mean/Min/Max/IntDen/RawIntDen are measured on the raw YH2AX
    // intensities (redirect), not on the binary image.
    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");

    run("Clear Results");
    n = nSlices;
    sumCount = 0;
    sumArea = 0;

    for (i = 1; i <= n; i++) {
        selectWindow(binaryStack);
        setSlice(i);

        print("[7] Analysing slice " + i + " of " + n);
        before = nResults;
        // "display" without "clear": rows accumulate across slices
        run("Analyze Particles...", "size=0.01-Infinity display");
        after = nResults;

        for (r = before; r < after; r++) {
            setResult("Slice", r, i);
            setResult("Foci No.", r, r - before + 1);
            sumArea += getResult("Area", r);
        }
        sumCount += (after - before);
    }

    // ---------- Rebuild the Results table in the order you want ----------
    total = nResults;
    sl = newArray(total);  fn = newArray(total);  ar = newArray(total);
    me = newArray(total);  mi = newArray(total);  mx = newArray(total);
    id = newArray(total);  rw = newArray(total);

    for (k = 0; k < total; k++) {
        sl[k] = getResult("Slice", k);
        fn[k] = getResult("Foci No.", k);
        ar[k] = getResult("Area", k);
        me[k] = getResult("Mean", k);
        mi[k] = getResult("Min", k);
        mx[k] = getResult("Max", k);
        id[k] = getResult("IntDen", k);
        rw[k] = getResult("RawIntDen", k);
    }

    run("Clear Results");
    for (k = 0; k < total; k++) {
        setResult("Image", k, imageName);
        setResult("Slice", k, sl[k]);
        setResult("Foci No.", k, fn[k]);
        setResult("Area", k, ar[k]);
        setResult("Mean", k, me[k]);
        setResult("Min", k, mi[k]);
        setResult("Max", k, mx[k]);
        setResult("IntDen", k, id[k]);
        setResult("RawIntDen", k, rw[k]);
    }
    updateResults();   // the "Results" window now holds every focus; copy/paste it into Excel

    // ---------- Per-focus CSV (appended across images) ----------
    fociCsv = File.getDirectory(yh2axPath) + "YH2AX_foci.csv";
    if (!File.exists(fociCsv))
        File.append("Image,Slice,Foci No.,Area,Mean,Min,Max,IntDen,RawIntDen", fociCsv);
    for (k = 0; k < total; k++)
        File.append(imageName + "," + sl[k] + "," + fn[k] + "," + ar[k] + ","
                    + me[k] + "," + mi[k] + "," + mx[k] + "," + id[k] + "," + rw[k], fociCsv);

    // Divide by however many slices were analysed
    meanCount = sumCount / n;
    meanArea  = sumArea  / n;

    // ---------- Per-image summary CSV (appended across images) ----------
    csvPath = File.getDirectory(yh2axPath) + "YH2AX_results.csv";
    if (!File.exists(csvPath))
        File.append("Image,NucLower,NucUpper,YH2AXLower,YH2AXUpper,Slices,MeanFociCount,MeanFociArea", csvPath);
    File.append(imageName + "," + nucLower + "," + nucUpper + ","
                + fociLower + "," + fociUpper + "," + n + ","
                + meanCount + "," + meanArea, csvPath);

    // ---------- Log: summary, tab-separated so it pastes into Excel ----------
    print("Image\tNucLower\tNucUpper\tYH2AXLower\tYH2AXUpper\tSlices\tMeanFociCount\tMeanFociArea");
    print(imageName + "\t" + nucLower + "\t" + nucUpper + "\t" + fociLower + "\t"
          + fociUpper + "\t" + n + "\t" + meanCount + "\t" + meanArea);
    print("Per-focus CSV: " + fociCsv);
    print("Per-image CSV: " + csvPath);
}
