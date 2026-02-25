% Demo: Reslice OCT volume to en-face view (looking down at tissue)
% This creates a view where each page shows the tissue surface (width × B-scans)
% and you scroll through pages to go deeper into the tissue

%% Setup
yOCTSetLibraryPath;

%% Create sample OCT data
fprintf('Creating sample OCT volume...\n');

zSize = 50;   % depth slices
xSize = 100;  % width
ySize = 80;   % B-scans

% Generate sample data with some structure
[X, Y, Z] = meshgrid(1:xSize, 1:ySize, 1:zSize);
sampleData = single(0.5 + 0.3*sin(X/10) .* cos(Y/8) .* exp(-Z/30));
sampleData = permute(sampleData, [3, 1, 2]); % Rearrange to (Z, X, Y)

% Create metadata
metadata.z.values = (0:zSize-1) * 0.01; % 0.5 mm total depth
metadata.z.index = 1:zSize;
metadata.z.units = 'mm';
metadata.z.order = 1;

metadata.x.values = (0:xSize-1) * 0.02; % 2.0 mm width
metadata.x.index = 1:xSize;
metadata.x.units = 'mm';
metadata.x.order = 2;

metadata.y.values = (0:ySize-1) * 0.02; % 1.6 mm B-scan range
metadata.y.index = 1:ySize;
metadata.y.units = 'mm';
metadata.y.order = 3;

clim = [0 1];

fprintf('Original volume: %d × %d × %d (Z, X, Y)\n', size(sampleData));
fprintf('  Depth: %.2f mm, Width: %.2f mm, B-scans: %.2f mm\n\n', ...
    range(metadata.z.values), range(metadata.x.values), range(metadata.y.values));

%% Save original B-scan view
outputFolder = 'TMP_ResliceDemo';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

originalFile = fullfile(outputFolder, 'original_bscan.tif');
fprintf('Saving original B-scan stack to: %s\n', originalFile);
yOCT2Tif(sampleData, originalFile, 'clim', clim, 'metadata', metadata);

%% Reslice to en-face view
enfaceFile = fullfile(outputFolder, 'enface_view.tif');
fprintf('Reslicing to en-face view (XYZ)...\n');
yOCTTransposeDimensions(originalFile, 'XYZ', 'outputPath', enfaceFile);

%% Load and display info
[enfaceData, enfaceMeta] = yOCTFromTif(enfaceFile);

fprintf('\nEn-face volume: %d × %d × %d\n', size(enfaceData));
fprintf('  Each page: %d × %d (width × B-scans)\n', size(enfaceData, 1), size(enfaceData, 2));
fprintf('  Number of depth slices: %d\n', size(enfaceData, 3));
fprintf('  Physical page size: %.2f × %.2f mm\n', ...
    range(enfaceMeta.z.values), range(enfaceMeta.x.values));
fprintf('  Depth range: %.2f mm\n', range(enfaceMeta.y.values));

%% Visualize comparison
figure('Name', 'Reslice Comparison', 'Position', [100 100 1200 500]);

% Original B-scan view
subplot(1, 2, 1);
imagesc(sampleData(:, :, round(end/2)));
title(sprintf('Original B-scan (Z×X) at Y=%d', round(ySize/2)));
xlabel('Width (X)');
ylabel('Depth (Z)');
colormap gray;
axis image;
colorbar;

% En-face view
subplot(1, 2, 2);
imagesc(enfaceData(:, :, round(end/2)));
title(sprintf('En-face view (X×Y) at depth=%d', round(zSize/2)));
xlabel('B-scans (Y)');
ylabel('Width (X)');
colormap gray;
axis image;
colorbar;

fprintf('\n=== Files created in %s ===\n', outputFolder);
fprintf('  %s - Original B-scan stack\n', originalFile);
fprintf('  %s - En-face view\n', enfaceFile);
fprintf('\nOpen these in ImageJ/Fiji to scroll through!\n');
