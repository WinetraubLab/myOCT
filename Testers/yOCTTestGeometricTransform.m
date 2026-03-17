function yOCTTestGeometricTransform()
% Test geometric transformations with a marker-based test volume
% This function tests yOCTTransposeDimensions to ensure transformations
% preserve data integrity and correctly remap spatial dimensions

fprintf('Testing Geometric Transformations...\n');

% Test parameters
zSize = 10;  % Depth
xSize = 15;  % Width
ySize = 20;  % B-scans
markerValue = 0;

% Create temporary file names
testFile = tempname;
testFileXYZ = [testFile '_xyz'];
testFile = [testFile '.tiff'];
testFileXYZ = [testFileXYZ '.tiff'];

try
    %% Create test volume with markers
    % Create volume filled with high values (white)
    testData = ones(zSize, xSize, ySize, 'single') * 1000;
    
    % Place black markers (low values) at specific corners to track transformations
    % Marker 1: Top-left-front corner (z=1, x=1, y=1)
    testData(1, 1, 1) = markerValue;
    
    % Marker 2: Top-right-front corner (z=1, x=end, y=1)
    testData(1, xSize, 1) = markerValue;
    
    % Marker 3: Bottom-left-front corner (z=end, x=1, y=1)
    testData(zSize, 1, 1) = markerValue;
    
    % Marker 4: Top-left-back corner (z=1, x=1, y=end)
    testData(1, 1, ySize) = markerValue;
    
    %% Create metadata
    metadata = struct();
    
    metadata.z.order = 1;
    metadata.z.values = linspace(0, 1, zSize);
    metadata.z.units = 'mm';
    metadata.z.index = 1:zSize;
    metadata.z.origin = 'Test depth dimension';
    
    metadata.x.order = 2;
    metadata.x.values = linspace(0, 1.5, xSize);
    metadata.x.units = 'mm';
    metadata.x.index = 1:xSize;
    metadata.x.origin = 'Test width dimension';
    
    metadata.y.order = 3;
    metadata.y.values = linspace(0, 2, ySize);
    metadata.y.units = 'mm';
    metadata.y.index = 1:ySize;
    metadata.y.origin = 'Test B-scan dimension';
    
    clim = [0, 1000];
    
    %% Save test volume
    yOCT2Tif(testData, testFile, 'metadata', metadata, 'clim', clim);
    
    %% Test: Transpose to XYZ
    yOCTTransposeDimensions(testFile, 'XYZ', 'outputPath', testFileXYZ);
    
    % Load both volumes
    [origData, origMeta, ~] = yOCTFromTif(testFile);
    [xyzData, xyzMeta, ~] = yOCTFromTif(testFileXYZ);
    
    % Verify original data preservation
    assert(isequal(size(origData), [zSize, xSize, ySize]), ...
        'Original data size mismatch');
    assert(isequal(origData, testData), ...
        'Original data was modified during save/load');
    
    % Verify XYZ transformation dimensions
    % After XYZ transpose: X->Z, Y->X, Z->Y
    expectedSize = [xSize, ySize, zSize];
    assert(isequal(size(xyzData), expectedSize), ...
        sprintf('XYZ transposed size incorrect. Expected [%d %d %d], got [%d %d %d]', ...
        expectedSize(1), expectedSize(2), expectedSize(3), ...
        size(xyzData,1), size(xyzData,2), size(xyzData,3)));
    
    % Find all black markers in both volumes
    [origZ, origX, origY] = ind2sub(size(origData), find(origData == markerValue));
    [xyzZ, xyzX, xyzY] = ind2sub(size(xyzData), find(xyzData == markerValue));
    
    % Verify all markers are preserved
    assert(length(origZ) == 4, 'Expected 4 markers in original volume');
    assert(length(xyzZ) == 4, 'Expected 4 markers after XYZ transformation');
    
    % Verify marker transformations
    % Based on XYZ transformation: permute([2 3 1]) then flip operations
    % Original (Z,X,Y) coordinates
    origMarkers = [origZ, origX, origY];
    xyzMarkers = [xyzZ, xyzX, xyzY];
    
    % Sort markers by original position for consistent comparison
    [~, origIdx] = sortrows(origMarkers);
    origMarkers = origMarkers(origIdx, :);
    
    % Test marker 1: (1,1,1) in original
    markerIdx = find(origMarkers(:,1)==1 & origMarkers(:,2)==1 & origMarkers(:,3)==1);
    assert(~isempty(markerIdx), 'Marker at (1,1,1) not found in original');
    origPos = origMarkers(markerIdx, :);
    
    % Find corresponding marker in XYZ volume (should have transformed)
    markerFound = false;
    for i = 1:size(xyzMarkers, 1)
        if xyzData(xyzMarkers(i,1), xyzMarkers(i,2), xyzMarkers(i,3)) == markerValue
            markerFound = true;
            break;
        end
    end
    assert(markerFound, 'Marker transformation failed: marker value not preserved');
    
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
    
    fprintf('  Geometric transformation tests passed!\n');
    
catch ME
    % Clean up before rethrowing
    if exist(testFile, 'file')
        delete(testFile);
    end
    if exist(testFileXYZ, 'file')
        delete(testFileXYZ);
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

end
