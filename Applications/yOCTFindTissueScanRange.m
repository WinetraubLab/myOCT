function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm] = yOCTFindTissueScanRange(varargin)
% yOCTFindTissueScanRange performs a low-resolution OCT overview scan,
% detects the tissue footprint, and returns tile-aligned scan ranges that
% cover the tissue. A summary PNG of the accepted range is saved next to
% the overview output for inspection.
%
% PIPELINE:
%   1. Scan overview tiles at a fixed Z depth with yOCTScanTile
%   2. Process scanned tiles to reconstruct volume with yOCTProcessTiledScan
%   3. Load processed volume with yOCTFromTif and detect tissue surface with yOCTFindTissueSurface
%   4. Detect tissue footprint and compute tile-aligned scan ranges
%
% NAME-VALUE INPUTS:
%   Name                    Default     Description
%   -- Scanning parameters ----------------------------------------------------------
%   octProbePath            ''          Path to probe .ini file required for scanning.
%   xRange_mm               [-3  3]     Overview scan range in X (mm).
%   yRange_mm               [-3  3]     Overview scan range in Y (mm).
%   pixelSize_um            20          XY pixel resolution for overview (µm).
%   scanTileSize_mm         0.5         FOV of each overview tile (mm).
%   tissueRefractiveIndex   1.33        Tissue refractive index.
%   -- Processing parameters ----------------------------------------------------------
%   dispersionQuadraticTerm []          Dispersion compensation [nm2/rad].
%                                       Required for scan and folder modes; ignored for .tif mode.
%   focusPositionInImageZpix []         Focus depth (pixels).
%                                       Required for scan and folder modes; ignored for .tif mode.
%   focusSigma              10          Z-stitching focus sigma (pixels).
%   -- Function-specific parameters ----------------------------------------------------------
%   temporaryFolderPath     ./Overview  Root temp folder for overview files.
%                                       If provided, files go to <temporaryFolderPath>\Overview\.
%                                       Default: .\Overview\ (relative to working directory).
%   preloadedScanPath       ''          Optional preloaded data to skip scanning part of the pipeline.
%   v                       false       Verbose mode.
%
% OUTPUTS:
%   xTissueRange_mm     [xMin xMax] X range covering detected tissue (mm)
%   yTissueRange_mm     [yMin yMax] Y range covering detected tissue (mm)
%   tissueCentroid_mm   [cx cy] tissue centroid in OCT coordinates (mm)

%% Parse inputs
p = inputParser;
% -- Scanning parameters -------------------------------------------------------
addParameter(p, 'octProbePath',              '',     @ischar);
addParameter(p, 'xRange_mm',                 [-3 3], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'yRange_mm',                 [-3 3], @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'pixelSize_um',              20,     @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'scanTileSize_mm',           0.5,    @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'tissueRefractiveIndex',     1.33,   @isnumeric);
% -- Processing parameters -----------------------------------------------------
addParameter(p, 'dispersionQuadraticTerm',   [],     @(x) isempty(x) || isnumeric(x));
addParameter(p, 'focusSigma',                10,     @isnumeric);
addParameter(p, 'focusPositionInImageZpix',  [],     @(x) isempty(x) || isnumeric(x));
% -- Function-specific parameters -----------------------------------------------
addParameter(p, 'temporaryFolderPath',       '',     @ischar);
addParameter(p, 'preloadedScanPath',         '',     @ischar);
addParameter(p, 'v',                         false,  @islogical);

parse(p, varargin{:});
in = p.Results;

overviewZ_um             = 40; % Z depth in microns for the single overview plane (must stay <100 um to prevent lens crash)
octProbePath             = in.octProbePath;
xRange_mm                = in.xRange_mm;
yRange_mm                = in.yRange_mm;
pixelSize_um             = in.pixelSize_um;
scanTileSize_mm          = in.scanTileSize_mm;
dispersionQuadraticTerm  = in.dispersionQuadraticTerm;
focusSigma               = in.focusSigma;
focusPositionInImageZpix = in.focusPositionInImageZpix;
preloadedScanPath        = in.preloadedScanPath;
v                        = in.v;

%% Validate inputs
% Get hardware status
[~, ~, skipHardware] = yOCTHardware('status');

% Check preloaded scans to skip scanning if required or skipHardware=true
analyzeTifOnly    = false;
analyzeFolderOnly = false;

if ~isempty(preloadedScanPath)
    [~, ~, ext] = fileparts(preloadedScanPath);
    if strcmpi(ext, '.tif') || strcmpi(ext, '.tiff')
        analyzeTifOnly = true;
    else
        % Folder path needs dispersion and focus for yOCTProcessTiledScan to process
        analyzeFolderOnly = true;
        if isempty(dispersionQuadraticTerm)
            error('yOCTFindTissueScanRange:missingDispersion', ...
                'dispersionQuadraticTerm is required when preloadedScanPath is a folder.');
        end
        if isempty(focusPositionInImageZpix)
            error('yOCTFindTissueScanRange:missingFocus', ...
                'focusPositionInImageZpix is required when preloadedScanPath is a folder.');
        end
    end
else
    % No preloadedScanPath needs hardware scan to get data, unless skipHardware = true
    if skipHardware
        warning('yOCTFindTissueScanRange:noVolumeToAnalyze', ...
            '%s Overview scan skipped: skipHardware=true and no preloadedScanPath provided. No tissue volume to analyze.', ...
            datestr(now));
        xTissueRange_mm   = [];
        yTissueRange_mm   = [];
        tissueCentroid_mm = [];
        return;
    end
    % Validate required scan parameters before touching hardware
    if isempty(octProbePath)
        error('yOCTFindTissueScanRange:missingOctProbePath', ...
            'octProbePath is required when preloadedScanPath is not set.');
    end
    if isempty(dispersionQuadraticTerm)
        error('yOCTFindTissueScanRange:missingDispersion', ...
            'dispersionQuadraticTerm is required when preloadedScanPath is not set. Measure it with yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm.');
    end
    if isempty(focusPositionInImageZpix)
        error('yOCTFindTissueScanRange:missingFocus', ...
            'focusPositionInImageZpix is required when preloadedScanPath is not set. Measure it with yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm.');
    end
end

%% Temporary folder setup
% If caller provides a root folder, create an Overview subfolder inside it.
if ~isempty(in.temporaryFolderPath)
    temporaryFolder = fullfile(in.temporaryFolderPath, 'Overview');
else
    temporaryFolder = './Overview';
end
overviewScanFolder   = [fullfile(temporaryFolder, 'OCTVolume'), filesep];
overviewProcessedTif = fullfile(temporaryFolder, sprintf('tissue_overview_%dum.tif', round(pixelSize_um)));
if analyzeFolderOnly
    overviewScanFolder = [fullfile(preloadedScanPath, 'OCTVolume'), filesep]; % OCTVolume subfolder inside the provided root folder
end

%% Perform tissue overview scan
if ~analyzeTifOnly && ~analyzeFolderOnly
    if ~skipHardware
        if ~exist(overviewScanFolder, 'dir')
            mkdir(overviewScanFolder);
        end
        if v
            fprintf('%s Scanning overview: X=[%.1f %.1f] Y=[%.1f %.1f] mm, %d µm pixels, z=%d µm\n', ...
                datestr(now), xRange_mm(1), xRange_mm(2), yRange_mm(1), yRange_mm(2), pixelSize_um, overviewZ_um);
        end
        yOCTScanTile( ...
            overviewScanFolder, ...
            xRange_mm, ...
            yRange_mm, ...
            'octProbePath',          octProbePath, ...
            'pixelSize_um',          pixelSize_um, ...
            'zDepths',               overviewZ_um * 1e-3, ...
            'tissueRefractiveIndex', in.tissueRefractiveIndex, ...
            'octProbeFOV_mm',        scanTileSize_mm, ...
            'unzipOCTFile',          true, ...
            'v',                     v);
    else
        if v
            fprintf('%s Hardware not initialized: skipping overview scan.\n', datestr(now));
        end
    end
end

%% Process tissue overview scan
if ~analyzeTifOnly
    if ~exist(temporaryFolder, 'dir')
        mkdir(temporaryFolder);
    end
    if v
        fprintf('%s Processing tissue overview scan...\n', datestr(now));
    end
    yOCTProcessTiledScan( ...
        overviewScanFolder, ...
        overviewProcessedTif, ...
        'dispersionQuadraticTerm',    dispersionQuadraticTerm, ...
        'focusSigma',                 focusSigma, ...
        'focusPositionInImageZpix',   focusPositionInImageZpix, ...
        'outputFilePixelSize_um',     [], ...
        'cropZRange_mm',              [], ...
        'v',                          v);
end

%% Detect tissue footprint and compute scan ranges
[xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm] = i_analyzeVolumeAndGetRanges( ...
    overviewProcessedTif, analyzeTifOnly, preloadedScanPath, ...
    overviewZ_um, scanTileSize_mm, pixelSize_um, temporaryFolder, ...
    xRange_mm, yRange_mm, v);

end % main function


%% LOCAL FUNCTIONS
%  Analyze overview volume: detect tissue and compute scan ranges
function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm] = i_analyzeVolumeAndGetRanges( ...
    overviewProcessedTif, analyzeTifOnly, preloadedScanPath, ...
    overviewZ_um, scanTileSize_mm, pixelSize_um, temporaryFolder, ...
    xRange_mm, yRange_mm, v)

% Load processed volume
if v
    fprintf('%s Loading overview volume...\n', datestr(now));
end

if analyzeTifOnly
    overviewProcessedTif = preloadedScanPath; % use the supplied .tif directly
end

[logMeanAbs, dimensions] = yOCTFromTif(overviewProcessedTif);

% Get overview volume for tissue detection and visualization
overviewZ_mm = overviewZ_um * 1e-3;
z     = dimensions.z.values(:);
zKeep = z >= overviewZ_mm;
logMeanAbs_overview   = logMeanAbs(zKeep, :, :);
dim_overview          = dimensions;
dim_overview.z.values = z(zKeep);
dim_overview.z.index  = dimensions.z.index(zKeep);

% Detect tissue surface
[surfacePosition_mm, x_mm, y_mm] = yOCTFindTissueSurface(logMeanAbs_overview, dim_overview, ...
    'octProbeFOV_mm', scanTileSize_mm);

% Extract XY en-face slice at overviewZ_mm for visualization
if isfield(dimensions, 'z') && isfield(dimensions.z, 'values')
    [~, zIdx] = min(abs(dimensions.z.values - overviewZ_mm));
else
    zIdx = 1;
end
xySlice = squeeze(logMeanAbs(zIdx, :, :))';   % (y, x)

% Detect tissue footprint
if v
    fprintf('%s Detecting tissue footprint...\n', datestr(now));
end

pixelSize_mm = mean(diff(x_mm(:)));
tissue_mask = i_detectTissueMask(surfacePosition_mm, pixelSize_mm, v);

if ~any(tissue_mask(:))
    error('yOCTFindTissueScanRange:noTissueDetected', ...
        'No tissue detected. Check scan range and tissue placement.');
end

% Tissue extent
colsWithTissue = any(tissue_mask, 1);
rowsWithTissue = any(tissue_mask, 2);
x_mm_row = x_mm(:)';
y_mm_col = y_mm(:);

% Save OCT en-face PNG with no overlays
rawPngPath = fullfile(temporaryFolder, sprintf('tissue_overview_%dum.png', round(pixelSize_um)));
if ~exist(temporaryFolder, 'dir')
    mkdir(temporaryFolder);
end
hRaw = figure('Visible', 'off', 'Position', [200 200 700 500]);
imagesc(x_mm_row, y_mm_col, xySlice);
colormap(gray);
axis equal tight;
xlabel('X (mm)'); ylabel('Y (mm)');
title('Tissue Overview - OCT en-face (XY)');
saveas(hRaw, rawPngPath);
close(hRaw);

% Compute tissue centroid and size
xMin_t = x_mm_row(find(colsWithTissue, 1, 'first'));
xMax_t = x_mm_row(find(colsWithTissue, 1, 'last'));
yMin_t = y_mm_col(find(rowsWithTissue, 1, 'first'));
yMax_t = y_mm_col(find(rowsWithTissue, 1, 'last'));

cx_mm = (xMin_t + xMax_t) / 2;
cy_mm = (yMin_t + yMax_t) / 2;
tissueCentroid_mm  = [cx_mm, cy_mm];
tissueWidth_mm     = xMax_t - xMin_t;
tissueHeight_mm    = yMax_t - yMin_t;

% Tile-aligned scan range
CENTROID_ROUND_MM = 0.05;
cx_r = round(cx_mm / CENTROID_ROUND_MM) * CENTROID_ROUND_MM;
cy_r = round(cy_mm / CENTROID_ROUND_MM) * CENTROID_ROUND_MM;

halfX_mm = ceil((tissueWidth_mm  / 2) / scanTileSize_mm) * scanTileSize_mm;
halfY_mm = ceil((tissueHeight_mm / 2) / scanTileSize_mm) * scanTileSize_mm;

xAutoRange_mm = [cx_r - halfX_mm,  cx_r + halfX_mm];
yAutoRange_mm = [cy_r - halfY_mm,  cy_r + halfY_mm];

% Shift range to stay within overview boundary (preserves span, shifts center)
xOverflowL = xRange_mm(1) - xAutoRange_mm(1);
xOverflowR = xAutoRange_mm(2) - xRange_mm(2);
yOverflowL = yRange_mm(1) - yAutoRange_mm(1);
yOverflowR = yAutoRange_mm(2) - yRange_mm(2);

if max(xOverflowL, xOverflowR) > scanTileSize_mm
    error('yOCTFindTissueScanRange:rangeExceedsOverview', ...
        'X scan range [%.3f %.3f] exceeds overview boundary by more than one tile. Widen xRange_mm.', ...
        xAutoRange_mm(1), xAutoRange_mm(2));
end
if max(yOverflowL, yOverflowR) > scanTileSize_mm
    error('yOCTFindTissueScanRange:rangeExceedsOverview', ...
        'Y scan range [%.3f %.3f] exceeds overview boundary by more than one tile. Widen yRange_mm.', ...
        yAutoRange_mm(1), yAutoRange_mm(2));
end

xAutoRange_mm = xAutoRange_mm + (max(0,xOverflowL) - max(0,xOverflowR));
yAutoRange_mm = yAutoRange_mm + (max(0,yOverflowL) - max(0,yOverflowR));
xAutoRange_mm = [max(xAutoRange_mm(1), xRange_mm(1)),  min(xAutoRange_mm(2), xRange_mm(2))];
yAutoRange_mm = [max(yAutoRange_mm(1), yRange_mm(1)),  min(yAutoRange_mm(2), yRange_mm(2))];

% Use the auto-detected, tile-aligned range as the accepted scan range
xTissueRange_mm = xAutoRange_mm;
yTissueRange_mm = yAutoRange_mm;

% Show detected tissue overview and results
i_showStaticOverviewFigure( ...
    xTissueRange_mm, yTissueRange_mm, ...
    surfacePosition_mm, x_mm_row, y_mm_col, ...
    xySlice, tissue_mask, ...
    tissueCentroid_mm, tissueWidth_mm, tissueHeight_mm, ...
    xAutoRange_mm, yAutoRange_mm, ...
    xRange_mm, yRange_mm, ...
    scanTileSize_mm, ...
    temporaryFolder);

nTileX = round(diff(xTissueRange_mm) / scanTileSize_mm);
nTileY = round(diff(yTissueRange_mm) / scanTileSize_mm);
fprintf('\nTissue Centroid: (%.2f, %.2f) mm\n', tissueCentroid_mm(1), tissueCentroid_mm(2));
fprintf('Tiles: %d x %d = %d  (%g mm each)\n\n', nTileX, nTileY, nTileX*nTileY, scanTileSize_mm);
fprintf('Accepted Tissue Ranges (mm):\n\n');
fprintf('  xOverall_mm = [%.2f  %.2f];\n', xTissueRange_mm(1), xTissueRange_mm(2));
fprintf('  yOverall_mm = [%.2f  %.2f];\n\n', yTissueRange_mm(1), yTissueRange_mm(2));

end % i_analyzeVolumeAndGetRanges

% Tissue detection
function tissue_mask = i_detectTissueMask(surfacePosition_mm, pixelSize_mm, v)
% Detect tissue footprint from the surface depth map.

[ny, nx] = size(surfacePosition_mm);
S     = surfacePosition_mm;
valid = ~isnan(S);

if ~any(valid(:))
    tissue_mask = false(ny, nx);
    return;
end

Svalid = S(valid);
p2  = prctile(Svalid,  2);   % minimum (ignore extreme outliers)
p98 = prctile(Svalid, 98);   % maximum

DEPTH_FRACTION = 0.15;  % keep pixels within the shallowest 15% of depth range
threshold = p2 + DEPTH_FRACTION * (p98 - p2);
candidate = (S <= threshold) & valid;

% Morphological cleanup
closeRad = max(1, round(0.30 / pixelSize_mm));
openRad  = max(1, round(0.20 / pixelSize_mm));
cleaned  = imclose(candidate, strel('disk', closeRad));
cleaned  = imopen(cleaned,    strel('disk', openRad));

% Largest connected component
CC = bwconncomp(cleaned);
tissue_mask = false(ny, nx);
if CC.NumObjects > 0
    [~, iL] = max(cellfun(@numel, CC.PixelIdxList));
    tissue_mask(CC.PixelIdxList{iL}) = true;
    if v && CC.NumObjects > 1
        fprintf('%s Tissue mask: kept largest of %d connected components.\n', datestr(now), CC.NumObjects);
    end
end

if ~any(tissue_mask(:))
    warning('yOCTFindTissueScanRange:noTissueAfterFiltering', ...
        'Tissue mask is empty. Try increasing DEPTH_FRACTION or reducing overviewZ_mm.');
end

if v
    fprintf('%s Detected tissue area: %.2f mm^2 (%.1f%% of overview).\n', ...
        datestr(now), sum(tissue_mask(:)) * pixelSize_mm^2, 100 * mean(tissue_mask(:)));
end

end % i_detectTissueMask

%  Create summary figure (shown after ranges are accepted)
function i_showStaticOverviewFigure( ...
    xTissueRange_mm, yTissueRange_mm, ...
    surfacePosition_mm, x_mm, y_mm, ...
    xySlice, tissue_mask, ...
    tissueCentroid_mm, tissueWidth_mm, tissueHeight_mm, ...
    xAutoRange_mm, yAutoRange_mm, ...
    overviewXRange_mm, overviewYRange_mm, ...
    scanTileSize_mm, ...
    temporaryFolder)

fig = figure('Name', 'Tissue Overview - Accepted Scan Range', ...
    'Position', [150 150 1050 500]);

octClim = prctile(xySlice(:), [1 99]);
if octClim(1) >= octClim(2), octClim(2) = octClim(1) + 0.001; end

% Left: OCT en-face + tissue mask + accepted range
ax1 = subplot(1, 2, 1, 'Parent', fig);
imagesc(ax1, x_mm, y_mm, xySlice);
colormap(ax1, 'gray');
clim(ax1, octClim);
hold(ax1, 'on');

% Tissue mask overlay (green)
tmRGB = cat(3, zeros(size(tissue_mask)), ones(size(tissue_mask)), zeros(size(tissue_mask)));
hm = imagesc(ax1, x_mm, y_mm, tmRGB);
set(hm, 'AlphaData', 0.3 * double(tissue_mask));
hMaskProxy = fill(ax1, NaN, NaN, [0 0.85 0], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', 'Tissue Mask');

% Detected range (dashed cyan)
xA = [xAutoRange_mm(1) xAutoRange_mm(2) xAutoRange_mm(2) xAutoRange_mm(1) xAutoRange_mm(1)];
yA = [yAutoRange_mm(1) yAutoRange_mm(1) yAutoRange_mm(2) yAutoRange_mm(2) yAutoRange_mm(1)];
hDetected = plot(ax1, xA, yA, '--c', 'LineWidth', 1, 'DisplayName', 'Detected Range');

% Accepted range (yellow)
xR = [xTissueRange_mm(1) xTissueRange_mm(2) xTissueRange_mm(2) xTissueRange_mm(1) xTissueRange_mm(1)];
yR = [yTissueRange_mm(1) yTissueRange_mm(1) yTissueRange_mm(2) yTissueRange_mm(2) yTissueRange_mm(1)];
hAccepted = plot(ax1, xR, yR, '-y', 'LineWidth', 2.5, 'DisplayName', 'Current Range');

hOrigin = plot(ax1, 0, 0, 'r.', 'MarkerSize', 18, 'DisplayName', 'Stage Origin');
hCentStat = plot(ax1, tissueCentroid_mm(1), tissueCentroid_mm(2), 'm+', ...
    'MarkerSize', 14, 'LineWidth', 2, 'DisplayName', ...
    sprintf('Tissue Centroid (%.2f, %.2f)', tissueCentroid_mm(1), tissueCentroid_mm(2)));
axis(ax1, 'equal', 'tight');
xlim(ax1, overviewXRange_mm + [-0.1 0.1]);
ylim(ax1, overviewYRange_mm + [-0.1 0.1]);
xlabel(ax1, 'X (mm)'); ylabel(ax1, 'Y (mm)');
title(ax1, sprintf('OCT en-face (XY) + tissue mask  |  tissue: %.1f x %.1f mm', ...
    tissueWidth_mm, tissueHeight_mm));
hold(ax1, 'off');

% Right: tile grid
ax2 = subplot(1, 2, 2, 'Parent', fig);
hold(ax2, 'on');

xEdges = xTissueRange_mm(1) : scanTileSize_mm : xTissueRange_mm(2);
yEdges = yTissueRange_mm(1) : scanTileSize_mm : yTissueRange_mm(2);

for xi = 1:length(xEdges)
    plot(ax2, [xEdges(xi) xEdges(xi)], yTissueRange_mm, '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
end
for yi = 1:length(yEdges)
    plot(ax2, xTissueRange_mm, [yEdges(yi) yEdges(yi)], '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
end
for xi = 1:length(xEdges)-1
    for yi = 1:length(yEdges)-1
        fill(ax2, ...
            [xEdges(xi) xEdges(xi+1) xEdges(xi+1) xEdges(xi)], ...
            [yEdges(yi) yEdges(yi) yEdges(yi+1) yEdges(yi+1)], ...
            [0.75 0.85 1.0], 'EdgeColor', [0.5 0.5 0.8], 'LineWidth', 0.5);
    end
end

plot(ax2, xR, yR, '-y', 'LineWidth', 2.5);
plot(ax2, 0, 0, 'r.', 'MarkerSize', 18);
plot(ax2, tissueCentroid_mm(1), tissueCentroid_mm(2), 'm+', 'MarkerSize', 14, 'LineWidth', 2);

axis(ax2, 'equal', 'tight');
xlim(ax2, overviewXRange_mm + [-0.1 0.1]);
ylim(ax2, overviewYRange_mm + [-0.1 0.1]);
set(ax2, 'YDir', 'reverse');
xlabel(ax2, 'X (mm)'); ylabel(ax2, 'Y (mm)');
nTileX = length(xEdges) - 1;
nTileY = length(yEdges) - 1;
title(ax2, sprintf('Tile grid: %d x %d = %d tiles  (%g mm each)', ...
    nTileX, nTileY, nTileX*nTileY, scanTileSize_mm));
hold(ax2, 'off');

% Reposition axes to make room for shared legend at bottom and sgtitle at top
ax1.Position = [0.05, 0.18, 0.43, 0.59];
ax2.Position = [0.55, 0.18, 0.43, 0.59];

% Shared horizontal legend centered below both subplots
hLeg = legend(ax1, [hDetected, hAccepted, hMaskProxy, hOrigin, hCentStat], ...
    'Orientation', 'horizontal', 'FontSize', 9, ...
    'Location', 'none', 'Units', 'normalized');
hLeg.Position(1) = 0.5 - hLeg.Position(3)/2;
hLeg.Position(2) = 0.03;

sgtitle(fig, sprintf('Overview Scan\nX = [%g  %g]  |  Y = [%g  %g]', ...
    xTissueRange_mm(1), xTissueRange_mm(2), yTissueRange_mm(1), yTissueRange_mm(2)), ...
    'FontWeight', 'bold');

% Save PNG summary of accepted ranges
saveas(fig, fullfile(temporaryFolder, 'tissue_ranges.png'));

end % i_showStaticOverviewFigure
