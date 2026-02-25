% Demo: Reslice OCT volume to en-face view (looking down at tissue)
% This creates a view where each page shows the tissue surface (width × B-scans)
% and you scroll through pages to go deeper into the tissue
%
% USAGE:
%   Demo_EnfaceReslice(inputTiffPath)
%
% INPUT:
%   inputTiffPath - path to TIFF file created by yOCT2Tif (B-scan stack)
%
% EXAMPLE:
%   Demo_EnfaceReslice('mydata.tif')

function Demo_EnfaceReslice(inputTiffPath)

%% Input validation
if nargin < 1
    error('Please provide input TIFF path. Usage: Demo_EnfaceReslice(''mydata.tif'')');
end

if ~exist(inputTiffPath, 'file')
    error('Input file not found: %s', inputTiffPath);
end

%% Setup
yOCTSetLibraryPath;

%% Load original data
fprintf('Loading original B-scan stack from: %s\n', inputTiffPath);
[sampleData, metadata, clim] = yOCTFromTif(inputTiffPath);

fprintf('Original volume: %d × %d × %d (Z, X, Y)\n', size(sampleData));
if ~isempty(metadata) && isfield(metadata, 'z') && isfield(metadata, 'x') && isfield(metadata, 'y')
    fprintf('  Depth: %.2f mm, Width: %.2f mm, B-scans: %.2f mm\n\n', ...
        range(metadata.z.values), range(metadata.x.values), range(metadata.y.values));
else
    fprintf('  (No metadata available)\n\n');
end

%% Reslice to en-face view
[inputFolder, inputName, inputExt] = fileparts(inputTiffPath);
if isempty(inputFolder)
    inputFolder = '.';
end

enfaceFile = fullfile(inputFolder, [inputName '_enface' inputExt]);
fprintf('Reslicing to en-face view (XYZ)...\n');
yOCTTransposeDimensions(inputTiffPath, 'XYZ', 'outputPath', enfaceFile);

%% Load and display info
[enfaceData, enfaceMeta] = yOCTFromTif(enfaceFile);

fprintf('\nEn-face volume: %d × %d × %d\n', size(enfaceData));
fprintf('  Each page: %d × %d (width × B-scans)\n', size(enfaceData, 1), size(enfaceData, 2));
fprintf('  Number of depth slices: %d\n', size(enfaceData, 3));
if ~isempty(enfaceMeta) && isfield(enfaceMeta, 'z') && isfield(enfaceMeta, 'x') && isfield(enfaceMeta, 'y')
    fprintf('  Physical page size: %.2f × %.2f mm\n', ...
        range(enfaceMeta.z.values), range(enfaceMeta.x.values));
    fprintf('  Depth range: %.2f mm\n', range(enfaceMeta.y.values));
end

%% Visualize comparison
figure('Name', 'Reslice Comparison', 'Position', [100 100 1200 500]);

% Original B-scan view
subplot(1, 2, 1);
midY = round(size(sampleData, 3) / 2);
imagesc(sampleData(:, :, midY));
title(sprintf('Original B-scan (Z×X) at Y=%d/%d', midY, size(sampleData, 3)));
xlabel('Width (X)');
ylabel('Depth (Z)');
colormap gray;
axis image;
colorbar;

% En-face view
subplot(1, 2, 2);
midZ = round(size(enfaceData, 3) / 2);
imagesc(enfaceData(:, :, midZ));
title(sprintf('En-face view (X×Y) at depth=%d/%d', midZ, size(enfaceData, 3)));
xlabel('B-scans (Y)');
ylabel('Width (X)');
colormap gray;
axis image;
colorbar;

fprintf('\n=== Files created ===\n');
fprintf('  Input:  %s\n', inputTiffPath);
fprintf('  Output: %s\n', enfaceFile);
fprintf('\nOpen the en-face file in ImageJ/Fiji to scroll through depth!\n');

end
