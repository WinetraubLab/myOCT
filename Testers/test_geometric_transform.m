% Test geometric transformations with a marker-based test volume
yOCTSetLibraryPath;

fprintf('=== CREATING TEST VOLUME WITH MARKERS ===\n\n');

% Create a small test volume (Z, X, Y) = (10, 15, 20)
zSize = 10;  % Depth
xSize = 15;  % Width
ySize = 20;  % B-scans

% Create volume filled with high values (white)
testData = ones(zSize, xSize, ySize, 'single') * 1000;

fprintf('Created test volume: %d × %d × %d (Z, X, Y)\n', zSize, xSize, ySize);
fprintf('  Z = Depth (pos 1)\n');
fprintf('  X = Width (pos 2)\n');
fprintf('  Y = B-scans (pos 3)\n\n');

% Place black markers (low values) at specific corners to track transformations
markerValue = 0;

% Marker 1: Top-left-front corner (z=1, x=1, y=1)
testData(1, 1, 1) = markerValue;
fprintf('Marker 1: BLACK pixel at (z=1, x=1, y=1) - Top-Left-Front corner\n');

% Marker 2: Top-right-front corner (z=1, x=end, y=1)
testData(1, xSize, 1) = markerValue;
fprintf('Marker 2: BLACK pixel at (z=1, x=%d, y=1) - Top-Right-Front corner\n', xSize);

% Marker 3: Bottom-left-front corner (z=end, x=1, y=1)
testData(zSize, 1, 1) = markerValue;
fprintf('Marker 3: BLACK pixel at (z=%d, x=1, y=1) - Bottom-Left-Front corner\n', zSize);

% Marker 4: Top-left-back corner (z=1, x=1, y=end)
testData(1, 1, ySize) = markerValue;
fprintf('Marker 4: BLACK pixel at (z=1, x=1, y=%d) - Top-Left-Back corner\n\n', ySize);

% Create fake metadata
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

% Save test volume
fprintf('Saving test volume to test_markers.tiff...\n');
yOCT2Tif(testData, 'test_markers.tiff', 'metadata', metadata, 'clim', clim);

% Transpose to XYZ
fprintf('\nTransposing with XYZ ordering (flip+rot90+flip)...\n');
yOCTTransposeDimensions('test_markers.tiff', 'XYZ', 'outputPath', 'test_markers_xyz.tiff');

% Load both volumes
fprintf('\n=== LOADING VOLUMES TO CHECK MARKER POSITIONS ===\n\n');
[origData, origMeta, ~] = yOCTFromTif('test_markers.tiff');
[xyzData, xyzMeta, ~] = yOCTFromTif('test_markers_xyz.tiff');

fprintf('Original volume: %d × %d × %d\n', size(origData));
fprintf('XYZ volume:      %d × %d × %d\n\n', size(xyzData));

% Find all black markers in both volumes
fprintf('=== ORIGINAL MARKER POSITIONS ===\n');
[origZ, origX, origY] = ind2sub(size(origData), find(origData == markerValue));
for i = 1:length(origZ)
    fprintf('Marker %d: (z=%d, x=%d, y=%d)\n', i, origZ(i), origX(i), origY(i));
end

fprintf('\n=== XYZ TRANSPOSED MARKER POSITIONS ===\n');
[xyzZ, xyzX, xyzY] = ind2sub(size(xyzData), find(xyzData == markerValue));
for i = 1:length(xyzZ)
    fprintf('Marker %d: (z=%d, x=%d, y=%d)\n', i, xyzZ(i), xyzX(i), xyzY(i));
end

fprintf('\n=== TRANSFORMATION MAPPING ===\n');
fprintf('Original (Z,X,Y) → XYZ Transposed (Z,X,Y)\n');
fprintf('─────────────────────────────────────────\n');
for i = 1:length(origZ)
    fprintf('(%2d,%2d,%2d) → (%2d,%2d,%2d)', ...
        origZ(i), origX(i), origY(i), xyzZ(i), xyzX(i), xyzY(i));
    
    % Verify the transformation
    % After permute [2 3 1]: orig(z,x,y) → new(x,y,z)
    % Then flip(dim2), rot90, flip(dim3)
    fprintf('\n');
end

fprintf('\n=== VISUAL VERIFICATION ===\n');
fprintf('Displaying first slice of each volume...\n\n');

figure('Name', 'Marker Transformation Test', 'Position', [100 100 1400 600]);

% Original - first B-scan (Z × X at y=1)
subplot(2, 3, 1);
imagesc(origData(:, :, 1)');
title('Original: First B-scan (y=1)');
xlabel('Z (depth)'); ylabel('X (width)');
colormap gray; axis image;
text(2, 2, 'M1', 'Color', 'red', 'FontSize', 14, 'FontWeight', 'bold');
text(2, xSize-1, 'M2', 'Color', 'red', 'FontSize', 14, 'FontWeight', 'bold');
text(zSize-1, 2, 'M3', 'Color', 'red', 'FontSize', 14, 'FontWeight', 'bold');

% XYZ - first slice (new Z × new X at new y=1)
subplot(2, 3, 4);
imagesc(xyzData(:, :, 1)');
title('XYZ: First slice (new y=1)');
xlabel('New Z (was X)'); ylabel('New X (was Y)');
colormap gray; axis image;

% Original - last B-scan (Z × X at y=end)
subplot(2, 3, 2);
imagesc(origData(:, :, end)');
title(sprintf('Original: Last B-scan (y=%d)', ySize));
xlabel('Z (depth)'); ylabel('X (width)');
colormap gray; axis image;
text(2, 2, 'M4', 'Color', 'red', 'FontSize', 14, 'FontWeight', 'bold');

% XYZ - last slice
subplot(2, 3, 5);
imagesc(xyzData(:, :, end)');
title(sprintf('XYZ: Last slice (new y=%d)', size(xyzData,3)));
xlabel('New Z (was X)'); ylabel('New X (was Y)');
colormap gray; axis image;

% Original - middle visualization
subplot(2, 3, 3);
imagesc(squeeze(origData(1, :, :))');
title('Original: Top surface (z=1)');
xlabel('X (width)'); ylabel('Y (B-scans)');
colormap gray; axis image;

% XYZ - middle visualization
subplot(2, 3, 6);
imagesc(squeeze(xyzData(1, :, :))');
title('XYZ: Front surface (new z=1)');
xlabel('New X (was Y)'); ylabel('New Y (was Z)');
colormap gray; axis image;

fprintf('Check the figure to visually verify marker positions!\n');
fprintf('\n=== TEST COMPLETE ===\n');
fprintf('Files created: test_markers.tiff, test_markers_xyz.tiff\n');
