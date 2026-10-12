// Optional: type a full path here to ALWAYS append summary rows to that one file,
// whichever folder your images are in, e.g. "/Users/you/Documents/Threshold Comparisons.csv".
// Leave "" to save YH2AX_results.csv next to each YH2AX image instead.
var masterCsv = "";

// If a text file was re-saved by Excel without a trailing newline, add one.
// (openAsString always ends with a newline; a shorter real file means it had none.)
function fixTrailingNewline(path) {
    if (File.exists(path)) {
        txt = File.openAsString(path);
        if (File.length(path) < lengthOf(txt))
            File.saveString(txt, path);
    }
}

// Append one line to a text file, starting on a new line.
function appendLine(line, path) {
    fixTrailingNewline(path);
    File.append(line, path);
}

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
        exit("No YH2AX threshold was set. Set it and leave the Threshold window on 'Set'/'Auto' (do NOT click Apply).");

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

    run("Clear Results");
    n = nSlices;
    sumCount = 0;
    sumArea = 0;

    // One array per column; each slice's foci are added in one go (fast even
    // when there are thousands of foci)
    aSlice = newArray(0);  aNo  = newArray(0);  aArea = newArray(0);
    aMean  = newArray(0);  aMin = newArray(0);  aMax  = newArray(0);
    aInt   = newArray(0);  aRaw = newArray(0);

    for (i = 1; i <= n; i++) {
        selectWindow(binaryStack);
        setSlice(i);
        showStatus("YH2AX: analysing slice " + i + " of " + n);

        // "clear": Results holds only this slice, read it straight away
        run("Analyze Particles...", "size=0.01-Infinity display clear");
        cnt = nResults;

        if (cnt > 0) {
            sSlice = newArray(cnt);  sNo  = newArray(cnt);  sArea = newArray(cnt);
            sMean  = newArray(cnt);  sMin = newArray(cnt);  sMax  = newArray(cnt);
            sInt   = newArray(cnt);  sRaw = newArray(cnt);
            for (r = 0; r < cnt; r++) {
                sSlice[r] = i;
                sNo[r]    = r + 1;
                sArea[r]  = getResult("Area", r);
                sMean[r]  = getResult("Mean", r);
                sMin[r]   = getResult("Min", r);
                sMax[r]   = getResult("Max", r);
                sInt[r]   = getResult("IntDen", r);
                sRaw[r]   = getResult("RawIntDen", r);
                sumArea  += sArea[r];
            }
            aSlice = Array.concat(aSlice, sSlice);  aNo   = Array.concat(aNo, sNo);
            aArea  = Array.concat(aArea, sArea);    aMean = Array.concat(aMean, sMean);
            aMin   = Array.concat(aMin, sMin);      aMax  = Array.concat(aMax, sMax);
            aInt   = Array.concat(aInt, sInt);      aRaw  = Array.concat(aRaw, sRaw);
        }
        sumCount += cnt;
    }
    total = sumCount;

    // Thousands of 1-pixel "foci" means the threshold is picking up background
    if (total > 5000) {
        if (!getBoolean("Found " + total + " foci - the YH2AX threshold is probably too low (background noise).\nContinue anyway?"))
            exit("Stopped. Run again and set a higher YH2AX lower threshold.");
    }

    // ---------- Build the final Results table in the order you want ----------
    run("Clear Results");
    for (k = 0; k < total; k++) {
        setResult("Area", k, aArea[k]);
        setResult("Mean", k, aMean[k]);
        setResult("Min", k, aMin[k]);
        setResult("Max", k, aMax[k]);
        setResult("IntDen", k, aInt[k]);
        setResult("RawIntDen", k, aRaw[k]);
    }
    updateResults();   // the "Results" window now holds every focus; copy/paste it into Excel

    // ---------- Per-focus CSV (appended across images) ----------
    // Summary CSV location: masterCsv (top of file) if set and its folder exists,
    // otherwise beside the YH2AX image.
    csvPath = masterCsv;
    if (csvPath != "" && !File.exists(File.getDirectory(csvPath)))
        csvPath = "";
    if (csvPath == "")
        csvPath = File.getDirectory(yh2axPath) + "YH2AX_results.csv";

    fociCsv = File.getDirectory(csvPath) + "YH2AX_foci.csv";
    fixTrailingNewline(fociCsv);
    if (!File.exists(fociCsv))
        File.append("Image,Slice,Foci No.,Area,Mean,Min,Max,IntDen,RawIntDen", fociCsv);
    chunk = "";
    inChunk = 0;
    for (k = 0; k < total; k++) {
        if (inChunk > 0)
            chunk = chunk + "\n";
        chunk = chunk + imageName + "," + aSlice[k] + "," + aNo[k] + "," + aArea[k] + ","
                + aMean[k] + "," + aMin[k] + "," + aMax[k] + "," + aInt[k] + "," + aRaw[k];
        inChunk++;
        if (inChunk == 500) {
            File.append(chunk, fociCsv);
            chunk = "";
            inChunk = 0;
        }
    }
    if (inChunk > 0)
        File.append(chunk, fociCsv);

    // Divide by however many slices were analysed
    meanCount = sumCount / n;
    meanArea  = sumArea  / n;

    // ---------- Per-image summary CSV (appended across images) ----------
    if (!File.exists(csvPath))
        appendLine("Image,Nuclear threshold lower,Nuclear threshold upper,YH2AX threshold lower,YH2AX threshold upper,Slices analysed,Mean foci count per slice,Mean foci area per slice", csvPath);
    appendLine(imageName + "," + nucLower + "," + nucUpper + ","
                + fociLower + "," + fociUpper + "," + n + ","
                + meanCount + "," + meanArea, csvPath);

    // ---------- Summary table: thresholds + averages (copy/paste into Excel) ----------
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

    // ---------- Log: summary, tab-separated so it pastes into Excel ----------
    print("Image\tNuclear threshold lower\tNuclear threshold upper\tYH2AX threshold lower\tYH2AX threshold upper\tSlices analysed\tMean foci count per slice\tMean foci area per slice");
    print(imageName + "\t" + nucLower + "\t" + nucUpper + "\t" + fociLower + "\t"
          + fociUpper + "\t" + n + "\t" + meanCount + "\t" + meanArea);
    print("Per-focus CSV: " + fociCsv);
    print("Per-image CSV: " + csvPath);
}
