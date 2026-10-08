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
    print("[6a] Setting measurements, redirect = " + yh2axStack);
    run("Set Measurements...",
        "area mean min integrated redirect=[" + yh2axStack + "] decimal=3");
    print("[6b] Measurements set");

    run("Clear Results");
    print("[6c] Results cleared");
    n = nSlices;
    sumCount = 0;
    sumArea = 0;

    // One array per column; every focus from every slice is appended to these
    aSlice = newArray(0);  aNo  = newArray(0);  aArea = newArray(0);
    aMean  = newArray(0);  aMin = newArray(0);  aMax  = newArray(0);
    aInt   = newArray(0);  aRaw = newArray(0);

    for (i = 1; i <= n; i++) {
        selectWindow(binaryStack);
        setSlice(i);

        // "clear": Results holds only this slice, read it straight away
        run("Analyze Particles...", "size=0.01-Infinity display clear");
        cnt = nResults;
        print("[7] Slice " + i + " of " + n + ": " + cnt + " foci");

        for (r = 0; r < cnt; r++) {
            a = getResult("Area", r);
            aSlice = Array.concat(aSlice, i);
            aNo    = Array.concat(aNo, r + 1);
            aArea  = Array.concat(aArea, a);
            aMean  = Array.concat(aMean, getResult("Mean", r));
            aMin   = Array.concat(aMin, getResult("Min", r));
            aMax   = Array.concat(aMax, getResult("Max", r));
            aInt   = Array.concat(aInt, getResult("IntDen", r));
            aRaw   = Array.concat(aRaw, getResult("RawIntDen", r));
            sumArea += a;
        }
        sumCount += cnt;
    }
    total = sumCount;
    print("[8] Measured " + total + " foci in total");

    // ---------- Build the final Results table in the order you want ----------
    run("Clear Results");
    for (k = 0; k < total; k++) {
        setResult("Image", k, imageName);
        setResult("Slice", k, aSlice[k]);
        setResult("Foci No.", k, aNo[k]);
        setResult("Area", k, aArea[k]);
        setResult("Mean", k, aMean[k]);
        setResult("Min", k, aMin[k]);
        setResult("Max", k, aMax[k]);
        setResult("IntDen", k, aInt[k]);
        setResult("RawIntDen", k, aRaw[k]);
    }
    updateResults();   // the "Results" window now holds every focus; copy/paste it into Excel
    print("[9] Results table built");

    // ---------- Per-focus CSV (appended across images) ----------
    fociCsv = File.getDirectory(yh2axPath) + "YH2AX_foci.csv";
    if (!File.exists(fociCsv))
        File.append("Image,Slice,Foci No.,Area,Mean,Min,Max,IntDen,RawIntDen", fociCsv);
    for (k = 0; k < total; k++)
        File.append(imageName + "," + aSlice[k] + "," + aNo[k] + "," + aArea[k] + ","
                    + aMean[k] + "," + aMin[k] + "," + aMax[k] + "," + aInt[k] + "," + aRaw[k], fociCsv);

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
    print("[10] Done");
}
