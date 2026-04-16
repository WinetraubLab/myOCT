function yOCTTestGeometricTransform()
% Test geometric transformations using the simulation and reconstruction flow.
% This function verifies yOCTTransposeDimensions with realistic metadata and
% confirms that ZXY -> XYZ -> ZXY returns to the original matrix.

% Test parameters
zSize = 256; % Depth
xSize = 64;  % Width
ySize = 8;   % B-scans

% Create temporary paths
tmpBase = tempname;
simFolder = [tmpBase '_sim'];
testFile = [tmpBase '_orig.tiff'];
testFileXYZ = [tmpBase '_xyz.tiff'];
testFileRoundTrip = [tmpBase '_zxy_roundtrip.tiff'];

try
    %% Create simulated test data and reconstruct to OCT TIFF
    % Use asymmetric marker locations to avoid accidental symmetry.
    testData = ones(zSize, xSize, ySize, 'single');
    markerValue = single(100);
    testData(40, 5, 2) = markerValue;
    testData(120, 20, 6) = markerValue;
    testData(200, 50, 7) = markerValue;

    octProbePath = yOCTGetProbeIniPath('40x', 'OCTP900');
    focusPositionInImageZpix = round(zSize/2);
    focusSigma = 1000;

    yOCTSimulateTileScan(testData, simFolder, ...
        'pixelSize_um', 1, ...
        'zDepths', 0, ...
        'focusPositionInImageZpix', focusPositionInImageZpix, ...
        'focusSigma', focusSigma, ...
        'octProbePath', octProbePath);

    yOCTProcessTiledScan(simFolder, {testFile}, ...
        'focusPositionInImageZpix', focusPositionInImageZpix, ...
        'focusSigma', focusSigma, ...
        'dispersionQuadraticTerm', 0, ...
        'v', false);
    
    %% Test: Transpose to XYZ
    yOCTTransposeDimensions(testFile, 'XYZ', 'outputPath', testFileXYZ);
    
    % Load both volumes
    [origData, origMeta, ~] = yOCTFromTif(testFile);
    [xyzData, xyzMeta, ~] = yOCTFromTif(testFileXYZ);
    
    % Verify XYZ transformation dimensions
    % After XYZ transpose: X->Z, Y->X, Z->Y
    expectedSize = [xSize, ySize, zSize];
    assert(isequal(size(xyzData), expectedSize), ...
        sprintf('XYZ transposed size incorrect. Expected [%d %d %d], got [%d %d %d]', ...
        expectedSize(1), expectedSize(2), expectedSize(3), ...
        size(xyzData,1), size(xyzData,2), size(xyzData,3)));
    
    % Verify metadata order was updated correctly
    assert(xyzMeta.x.order == 1, 'XYZ metadata: X order should be 1');
    assert(xyzMeta.y.order == 2, 'XYZ metadata: Y order should be 2');
    assert(xyzMeta.z.order == 3, 'XYZ metadata: Z order should be 3');
    
    % Verify metadata dimensions match data
    assert(length(xyzMeta.x.values) == size(xyzData, 1), ...
        'XYZ metadata: X dimension size mismatch');
    assert(length(xyzMeta.y.values) == size(xyzData, 2), ...
        'XYZ metadata: Y dimension size mismatch');
    assert(length(xyzMeta.z.values) == size(xyzData, 3), ...
        'XYZ metadata: Z dimension size mismatch');
    
    % Verify physical spacing is preserved
    assert(length(xyzMeta.x.values) == xSize, ...
        'XYZ: X values count should match original X dimension');
    assert(length(xyzMeta.y.values) == ySize, ...
        'XYZ: Y values count should match original Y dimension');
    assert(length(xyzMeta.z.values) == zSize, ...
        'XYZ: Z values count should match original Z dimension');

    %% Test round-trip: ZXY -> XYZ -> ZXY
    yOCTTransposeDimensions(testFileXYZ, 'ZXY', 'outputPath', testFileRoundTrip);
    [roundTripData, roundTripMeta, ~] = yOCTFromTif(testFileRoundTrip);

    assert(isequal(size(roundTripData), size(origData)), ...
        'Round-trip size mismatch after ZXY -> XYZ -> ZXY');
    assert(isequal(roundTripData, origData), ...
        'Round-trip data mismatch after ZXY -> XYZ -> ZXY');

    assert(roundTripMeta.z.order == 1, 'Round-trip metadata: Z order should be 1');
    assert(roundTripMeta.x.order == 2, 'Round-trip metadata: X order should be 2');
    assert(roundTripMeta.y.order == 3, 'Round-trip metadata: Y order should be 3');
    
    fprintf('  Geometric transformation tests passed!\n');
    
    if exist(testFile, 'file')
        delete(testFile);
    end
    if exist(testFileXYZ, 'file')
        delete(testFileXYZ);
    end
    if exist(testFileRoundTrip, 'file')
        delete(testFileRoundTrip);
    end
    if exist(simFolder, 'dir')
        rmdir(simFolder, 's');
    end
    rethrow(ME);
end

%% Clean up test files
if exist(testFile, 'file')
    delete(testFile);
end
if exist(testFileXYZ, 'file')
    delete(testFileXYZ);
end
if exist(testFileRoundTrip, 'file')
    delete(testFileRoundTrip);
end
if exist(simFolder, 'dir')
    rmdir(simFolder, 's');
end

end
