% Script to process and combine OCT tiles from Image.tiff.fldr
% 
% MODES:
%   1. CROP MODE: If zCropStart and zCropEnd have values -> crops each tile's Z dimension
%   2. COPY MODE: If either zCropStart or zCropEnd is empty/NaN -> copies tiles without cropping
%
% PROCESS:
%   - Reads tiles from Image.tiff.fldr
%   - Creates Image_FINAL folder with processed tiles
%   - Combines all tiles into single output file
%
% OUTPUT:
%   - Image_FINAL/ folder with individual tiles + metadata
%   - Single combined TIFF file in basePath

%% ========== CONFIGURATION ==========
% Base path containing Image.tiff.fldr
basePath = 'F:\Large_20x\20x\5x5';

% Z crop range (set to [] or NaN to disable cropping)
% Example: zCropStart = 320; zCropEnd = 700;  -> crops Z from 320 to 700
%          zCropStart = []; zCropEnd = [];    -> no cropping mode
zCropStart = 320;
zCropEnd = 700;

% Output filename for combined TIFF
outputFileName = 'Image_Combined.tiff';

%% ========== START PROCESSING ==========
fprintf('\n========================================\n');
fprintf('OCT Tile Processing and Combination\n');
fprintf('========================================\n');
fprintf('Base path: %s\n', basePath);

tic(); % Start timer

%% Determine processing mode
doCrop = ~isempty(zCropStart) && ~isnan(zCropStart) && ...
         ~isempty(zCropEnd) && ~isnan(zCropEnd);

if doCrop
    fprintf('\n>>> MODE: CROP\n');
    fprintf('  Will crop Z dimension from %d to %d\n', zCropStart, zCropEnd);
else
    fprintf('\n>>> MODE: COPY (No Cropping)\n');
    fprintf('  Will copy original tiles without modification\n');
end

%% Define paths
inputFolder = fullfile(basePath, 'Image.tiff.fldr');
workFolder = fullfile(basePath, 'Image_FINAL');
outputFile = fullfile(basePath, outputFileName);

fprintf('\nInput folder:  %s\n', inputFolder);
fprintf('Work folder:   %s\n', workFolder);
fprintf('Output file:   %s\n', outputFile);

% Verify input folder exists
if ~exist(inputFolder, 'dir')
    error('ERROR: Input folder not found: %s', inputFolder);
end

%% Load metadata from input folder
fprintf('\n%s Loading metadata from input folder...\n', datestr(datetime));
metadataFile = fullfile(inputFolder, 'TifMetadata.json');
if ~exist(metadataFile, 'file')
    error('ERROR: TifMetadata.json not found in input folder');
end

metadataStruct = jsondecode(fileread(metadataFile));
metadata = metadataStruct.metadata;

% Get dimensions
numYPlanes = length(metadata.y.index);
fprintf('  Y planes: %d\n', numYPlanes);

% Read first tile to get Z and X dimensions
firstTile = fullfile(inputFolder, 'y0001.tif');
if ~exist(firstTile, 'file')
    error('ERROR: First tile not found: %s', firstTile);
end

info = imfinfo(firstTile);
numZOriginal = info(1).Height;
numX = info(1).Width;
fprintf('  Original tile size: Z=%d, X=%d\n', numZOriginal, numX);

% Calculate output dimensions
if doCrop
    zCropStart = max(1, min(zCropStart, numZOriginal));
    zCropEnd = max(zCropStart, min(zCropEnd, numZOriginal));
    numZ = zCropEnd - zCropStart + 1;
    fprintf('  Output tile size: Z=%d (cropped from %d to %d)\n', numZ, zCropStart, zCropEnd);
    fprintf('  Memory reduction: %.1f%%\n', 100 * (1 - numZ/numZOriginal));
else
    numZ = numZOriginal;
    zCropStart = 1;
    zCropEnd = numZOriginal;
    fprintf('  Output tile size: Z=%d (no cropping)\n', numZ);
end

fprintf('\nFinal volume dimensions:\n');
fprintf('  Z = %d pixels\n', numZ);
fprintf('  X = %d pixels\n', numX);
fprintf('  Y = %d planes\n', numYPlanes);
fprintf('  Estimated memory: %.2f GB\n', numZ * numX * numYPlanes * 4 / (1024^3));

%% Check if work folder exists and verify contents
skipProcessing = false;
if exist(workFolder, 'dir')
    fprintf('\n%s Work folder already exists, checking contents...\n', datestr(datetime));
    
    % Check if TifMetadata.json exists
    workMetadataFile = fullfile(workFolder, 'TifMetadata.json');
    if ~exist(workMetadataFile, 'file')
        fprintf('  WARNING: TifMetadata.json missing, will recreate folder\n');
        rmdir(workFolder, 's');
    else
        % Verify all tiles exist
        allTilesExist = true;
        for yI = 1:numYPlanes
            tileFile = fullfile(workFolder, sprintf('y%04d.tif', yI));
            if ~exist(tileFile, 'file')
                allTilesExist = false;
                break;
            end
        end
        
        if allTilesExist
            fprintf('  All %d tiles found in work folder\n', numYPlanes);
            
            % Verify tile dimensions match expected output
            testTile = fullfile(workFolder, 'y0001.tif');
            testInfo = imfinfo(testTile);
            if testInfo(1).Height == numZ && testInfo(1).Width == numX
                fprintf('  Tile dimensions match (Z=%d, X=%d)\n', numZ, numX);
                fprintf('  >>> Skipping tile processing, using existing tiles\n');
                skipProcessing = true;
            else
                fprintf('  WARNING: Tile dimensions mismatch (found Z=%d, expected Z=%d)\n', ...
                    testInfo(1).Height, numZ);
                fprintf('  Will recreate folder\n');
                rmdir(workFolder, 's');
            end
        else
            fprintf('  WARNING: Some tiles missing, will recreate folder\n');
            rmdir(workFolder, 's');
        end
    end
end

%% Process tiles (crop or copy)
if ~skipProcessing
    fprintf('\n%s Processing tiles...\n', datestr(datetime));
    
    % Create work folder
    if exist(workFolder, 'dir')
        rmdir(workFolder, 's');
    end
    mkdir(workFolder);
    
    % Process tiles with parallel processing
    printEveryN = max(floor(numYPlanes/20), 1);
    
    if doCrop
        fprintf('  Cropping %d tiles (Z: %d to %d)...\n', numYPlanes, zCropStart, zCropEnd);
    else
        fprintf('  Copying %d tiles (no cropping)...\n', numYPlanes);
    end
    
    parfor yI = 1:numYPlanes
        % Read tile
        inputTile = fullfile(inputFolder, sprintf('y%04d.tif', yI));
        tile = imread(inputTile);
        
        % Process tile (crop or keep original)
        if doCrop
            tileProcessed = tile(zCropStart:zCropEnd, :);
        else
            tileProcessed = tile;
        end
        
        % Write to work folder
        outputTile = fullfile(workFolder, sprintf('y%04d.tif', yI));
        imwrite(tileProcessed, outputTile, 'tif', 'Compression', 'none');
        
        % Progress (only print every N tiles)
        if mod(yI, printEveryN) == 0
            fprintf('    Processed %d/%d tiles (%.1f%%)\n', yI, numYPlanes, 100*yI/numYPlanes);
        end
    end
    
    fprintf('  Done! All %d tiles processed\n', numYPlanes);
    
    % Update metadata for output tiles
    fprintf('\n%s Writing metadata...\n', datestr(datetime));
    metadataOutput = metadata;
    if doCrop
        % Update Z dimension
        metadataOutput.z.values = metadata.z.values(zCropStart:zCropEnd);
        metadataOutput.z.index = 1:numZ;
        metadataOutput.z.indexMax = ceil(numZ / 1000);
    end
    
    % Write metadata to work folder
    metadataStructOutput.metadata = metadataOutput;
    metadataStructOutput.clim = metadataStruct.clim;
    metadataStructOutput.version = metadataStruct.version;
    
    workMetadataFile = fullfile(workFolder, 'TifMetadata.json');
    fid = fopen(workMetadataFile, 'w');
    fprintf(fid, '%s', jsonencode(metadataStructOutput));
    fclose(fid);
    fprintf('  Metadata written to: %s\n', workMetadataFile);
else
    fprintf('\n%s Using existing tiles, loading metadata...\n', datestr(datetime));
    workMetadataFile = fullfile(workFolder, 'TifMetadata.json');
    metadataStructOutput = jsondecode(fileread(workMetadataFile));
    metadataOutput = metadataStructOutput.metadata;
end

%% Combine tiles into single TIFF file (Phase 3)
fprintf('\n%s Combining tiles into single TIFF file...\n', datestr(datetime));
fprintf('  Loading all %d tiles into memory...\n', numYPlanes);

% Prepare dimension info
dims.x = metadataOutput.x;
dims.y = metadataOutput.y;
dims.z = metadataOutput.z;

% Load all tiles using yOCTFromTif
% Since workFolder has no extension, yOCTFromTif treats it as folder
fprintf('  Calling yOCTFromTif to load volume...\n');
try
    scanVolume = yOCTFromTif(workFolder, 'yI', 1:numYPlanes, 'isCheckMetadata', false);
    fprintf('  Loaded! Volume size: [%d, %d, %d]\n', size(scanVolume,1), size(scanVolume,2), size(scanVolume,3));
catch ME
    fprintf('ERROR loading tiles with yOCTFromTif:\n');
    fprintf('  Message: %s\n', ME.message);
    error('Failed to load tiles. Check that Image_FINAL contains valid tiles.');
end

% Get clim from metadata
if isfield(metadataStructOutput, 'clim') && ~isempty(metadataStructOutput.clim)
    clim = metadataStructOutput.clim;
    fprintf('  Using clim from metadata: [%.4f, %.4f]\n', clim(1), clim(2));
else
    % Calculate from data
    clim = [min(scanVolume(:)), max(scanVolume(:))];
    fprintf('  Calculated clim from data: [%.4f, %.4f]\n', clim(1), clim(2));
end

% Save combined volume using yOCT2Tif
fprintf('\n%s Saving combined TIFF file...\n', datestr(datetime));
fprintf('  Output: %s\n', outputFile);

yOCT2Tif(scanVolume, outputFile, 'clim', clim, 'metadata', dims);

%% Done
totalTime = toc()/60;
fprintf('\n========================================\n');
fprintf('%s COMPLETED SUCCESSFULLY!\n', datestr(datetime));
fprintf('========================================\n');
fprintf('Work folder: %s\n', workFolder);
fprintf('  Contains %d individual tiles + metadata\n', numYPlanes);
fprintf('\nOutput file: %s\n', outputFile);
fprintf('  Final size: Z=%d, X=%d, Y=%d\n', numZ, numX, numYPlanes);
fprintf('\nTotal processing time: %.1f minutes\n', totalTime);
fprintf('========================================\n\n');
