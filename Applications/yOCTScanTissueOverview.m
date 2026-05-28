function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm, tissueArea_mm2] = yOCTScanTissueOverview(varargin)
% yOCTScanTissueOverview performs a low-resolution OCT overview scan,
% detects the tissue footprint, and returns tile-aligned scan ranges that
% cover the tissue. Summary PNG is stored on the pwd folder.
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
%   focusSigma              10          Z-stitching focus sigma (pixels). Objective-dependent:
%                                         10x: 20 | 20x: 10 | 40x: 10 or 1
%   -- Function-specific parameters ----------------------------------------------------------
%   temporaryFolderPath     ./Overview  Root temp folder for overview files.
%                                       If provided, files go to <temporaryFolderPath>\Overview\.
%                                       Default: .\Overview\ (relative to working directory).
%   preloadedScanPath       ''          Optional preloaded data to skip scanning part of the pipeline.
%   v                       false       Verbose mode. When true, summary figures are also shown on screen.
%
% GENERATED FILES:
%   tissue_overview_<N>um.png   OCT en-face XY slice overview image.
%   tissue_ranges.png           Tissue mask, detected scan range, and tile grid figure image.
%
% OUTPUTS:
%   xTissueRange_mm     [xMin xMax] X range covering detected tissue (mm)
%   yTissueRange_mm     [yMin yMax] Y range covering detected tissue (mm)
%   tissueCentroid_mm   [cx cy] tissue centroid in OCT coordinates (mm)
%   tissueArea_mm2      Area of the detected tissue footprint (mm^2)

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
% Get hardware status.
try
    [~, ~, skipHardware] = yOCTHardware('status');
catch
    skipHardware = true;
end

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
            error('yOCTScanTissueOverview:missingDispersion', ...
                'dispersionQuadraticTerm is required when preloadedScanPath is a folder.');
        end
        if isempty(focusPositionInImageZpix)
            error('yOCTScanTissueOverview:missingFocus', ...
                'focusPositionInImageZpix is required when preloadedScanPath is a folder.');
        end
    end
else
    % No preloadedScanPath needs hardware scan to get data, unless skipHardware = true
    if skipHardware
        warning('yOCTScanTissueOverview:noVolumeToAnalyze', ...
            '%s Overview scan skipped: skipHardware=true and no preloadedScanPath provided. No tissue volume to analyze.', ...
            datestr(now));
        xTissueRange_mm   = [];
        yTissueRange_mm   = [];
        tissueCentroid_mm = [];
        tissueArea_mm2    = [];
        return;
    end
    % Validate required scan parameters before touching hardware
    if isempty(octProbePath)
        error('yOCTScanTissueOverview:missingOctProbePath', ...
            'octProbePath is required when preloadedScanPath is not set.');
    end
    if isempty(dispersionQuadraticTerm)
        error('yOCTScanTissueOverview:missingDispersion', ...
            'dispersionQuadraticTerm is required when preloadedScanPath is not set. Measure it with yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm.');
    end
    if isempty(focusPositionInImageZpix)
        error('yOCTScanTissueOverview:missingFocus', ...
            'focusPositionInImageZpix is required when preloadedScanPath is not set. Measure it with yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm.');
    end
end

%% Temporary folder setup
% Priority: explicit temporaryFolderPath > next to the preloaded .tif > ./Overview
if ~isempty(in.temporaryFolderPath)
    temporaryFolder = fullfile(in.temporaryFolderPath, 'Overview');
elseif analyzeTifOnly
    % Save outputs in the same folder as the provided .tif file.
    temporaryFolder = fileparts(preloadedScanPath);
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
% Resolve which processed .tif to analyze: either the one we just produced
% above, or the one the caller provided via preloadedScanPath.
if analyzeTifOnly
    processedTifPath = preloadedScanPath;
else
    processedTifPath = overviewProcessedTif;
end

[xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm, tissueArea_mm2] = detectTissueScanRange( ...
    processedTifPath, overviewZ_um, scanTileSize_mm, xRange_mm, yRange_mm, temporaryFolder, v);

end % main function


    %% LOCAL FUNCTIONS
    % Load the processed overview tif, detect the tissue footprint, and return a
    % tile-aligned scan range that covers it. Also saves two PNGs into
    % temporaryFolder: the raw en-face image and a summary with the accepted range.
    function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm, tissueArea_mm2] = detectTissueScanRange( ...
        processedTifPath, overviewZ_um, scanTileSize_mm, xRange_mm, yRange_mm, temporaryFolder, v)

    figureVisibility = ternary(v, 'on', 'off');

    %% Load processed volume
    if v
        fprintf('%s Loading overview volume...\n', datestr(now));
    end
    [logMeanAbs, dimensions] = yOCTFromTif(processedTifPath);

    % Get overview volume for tissue detection and visualization
    overviewZ_mm = overviewZ_um * 1e-3;
    z     = dimensions.z.values(:);
    zKeep = z >= overviewZ_mm;
    logMeanAbs_overview   = logMeanAbs(zKeep, :, :);
    dim_overview          = dimensions;
    dim_overview.z.values = z(zKeep);
    dim_overview.z.index  = dimensions.z.index(zKeep);

    %% Detect tissue surface
    [surfacePosition_mm, x_mm, y_mm] = yOCTFindTissueSurface(logMeanAbs_overview, dim_overview, ...
        'octProbeFOV_mm', scanTileSize_mm);

    % Extract XY en-face slice at overviewZ_mm for visualization
    if isfield(dimensions, 'z') && isfield(dimensions.z, 'values')
        [~, zIdx] = min(abs(dimensions.z.values - overviewZ_mm));
    else
        zIdx = 1;
    end
    xySlice = squeeze(logMeanAbs(zIdx, :, :))';   % (y, x)

    %% Detect tissue footprint
    if v
        fprintf('%s Detecting tissue footprint...\n', datestr(now));
    end

    pixelSize_mm = mean(diff(x_mm(:)));
    tissue_mask = detectTissueMask(surfacePosition_mm, pixelSize_mm, v);

    if ~any(tissue_mask(:))
        error('yOCTScanTissueOverview:noTissueDetected', ...
            'No tissue detected. Check scan range and tissue placement.');
    end

    % Warn if a significant fraction of tissue pixels touch any edge of the
    % overview scan: this suggests the scan range was too narrow and tissue
    % may have been cut off.
    borderPx = max(1, round(0.5 / pixelSize_mm));
    CLIP_FRACTION = 0.30; % warn if >30% of tissue is in the border strip
    tissuePx = sum(tissue_mask(:));
    borderStrips = {tissue_mask(:, 1:borderPx),            'left';
                    tissue_mask(:, end-borderPx+1:end),    'right';
                    tissue_mask(1:borderPx, :),            'top';
                    tissue_mask(end-borderPx+1:end, :),    'bottom'};
    for k = 1:size(borderStrips, 1)
        if sum(borderStrips{k,1}(:)) / tissuePx > CLIP_FRACTION
            warning('yOCTScanTissueOverview:tissueClipped', ...
                'Tissue mask has significant presence at the %s edge of the overview scan. The scan range may not cover all tissue — consider widening %sRange_mm.', ...
                borderStrips{k,2}, borderStrips{k,2}(1)); % 'left'/'right' -> 'x', 'top'/'bottom' -> 'y'
        end
    end

    % Tissue extent, centroid, size & area
    colsWithTissue = any(tissue_mask, 1);
    rowsWithTissue = any(tissue_mask, 2);
    x_mm_row = x_mm(:)';
    y_mm_col = y_mm(:);

    xMin_t = x_mm_row(find(colsWithTissue, 1, 'first'));
    xMax_t = x_mm_row(find(colsWithTissue, 1, 'last'));
    yMin_t = y_mm_col(find(rowsWithTissue, 1, 'first'));
    yMax_t = y_mm_col(find(rowsWithTissue, 1, 'last'));

    cx_mm = (xMin_t + xMax_t) / 2;
    cy_mm = (yMin_t + yMax_t) / 2;
    tissueCentroid_mm  = [cx_mm, cy_mm];
    tissueWidth_mm     = xMax_t - xMin_t;
    tissueHeight_mm    = yMax_t - yMin_t;
    tissueArea_mm2     = sum(tissue_mask(:)) * pixelSize_mm^2;

    %% Save raw OCT en-face PNG
    if ~exist(temporaryFolder, 'dir')
        mkdir(temporaryFolder);
    end
    rawPngPath = fullfile(temporaryFolder, 'tissue_overview.png');
    hRaw = figure('Visible', figureVisibility, 'Position', [200 200 700 500]);
    imagesc(x_mm_row, y_mm_col, xySlice);
    colormap(gray);
    axis equal tight;
    xlabel('X (mm)'); ylabel('Y (mm)');
    title(sprintf('Tissue Overview - OCT en-face (XY) at %g µm/pixel', round(pixelSize_mm * 1e3)));
    saveas(hRaw, rawPngPath);
    if ~v, close(hRaw); end

    %% Compute tile-aligned scan range, clamped to the overview boundary
    % Use the requested scan range as the boundary, not the actual
    % pixel grid extent. The requested range is always a whole
    % number of tiles; the pixel grid is not, and clamping to it breaks that.
    overviewXRange_mm = xRange_mm;
    overviewYRange_mm = yRange_mm;

    CENTROID_ROUND_MM = 0.05;
    cx_r = round(cx_mm / CENTROID_ROUND_MM) * CENTROID_ROUND_MM;
    cy_r = round(cy_mm / CENTROID_ROUND_MM) * CENTROID_ROUND_MM;

    halfX_mm = ceil((tissueWidth_mm  / 2) / scanTileSize_mm) * scanTileSize_mm;
    halfY_mm = ceil((tissueHeight_mm / 2) / scanTileSize_mm) * scanTileSize_mm;

    xAutoRange_mm = [cx_r - halfX_mm,  cx_r + halfX_mm];
    yAutoRange_mm = [cy_r - halfY_mm,  cy_r + halfY_mm];

    % Shift range to stay within overview boundary (preserves span, shifts center)
    xOverflowL = overviewXRange_mm(1) - xAutoRange_mm(1);
    xOverflowR = xAutoRange_mm(2) - overviewXRange_mm(2);
    yOverflowL = overviewYRange_mm(1) - yAutoRange_mm(1);
    yOverflowR = yAutoRange_mm(2) - overviewYRange_mm(2);

    if max(xOverflowL, xOverflowR) > scanTileSize_mm
        error('yOCTScanTissueOverview:rangeExceedsOverview', ...
            'X scan range [%.3f %.3f] exceeds overview boundary by more than one tile. Widen xRange_mm.', ...
            xAutoRange_mm(1), xAutoRange_mm(2));
    end
    if max(yOverflowL, yOverflowR) > scanTileSize_mm
        error('yOCTScanTissueOverview:rangeExceedsOverview', ...
            'Y scan range [%.3f %.3f] exceeds overview boundary by more than one tile. Widen yRange_mm.', ...
            yAutoRange_mm(1), yAutoRange_mm(2));
    end

    xAutoRange_mm = xAutoRange_mm + (max(0,xOverflowL) - max(0,xOverflowR));
    yAutoRange_mm = yAutoRange_mm + (max(0,yOverflowL) - max(0,yOverflowR));
    xAutoRange_mm = [max(xAutoRange_mm(1), overviewXRange_mm(1)),  min(xAutoRange_mm(2), overviewXRange_mm(2))];
    yAutoRange_mm = [max(yAutoRange_mm(1), overviewYRange_mm(1)),  min(yAutoRange_mm(2), overviewYRange_mm(2))];

    % Use the auto-detected, tile-aligned range
    xTissueRange_mm = xAutoRange_mm;
    yTissueRange_mm = yAutoRange_mm;

    %% Save summary figure (detected range + tile grid)
    saveScanRangeFigure( ...
        xTissueRange_mm, yTissueRange_mm, ...
        x_mm_row, y_mm_col, xySlice, tissue_mask, ...
        tissueCentroid_mm, tissueArea_mm2, pixelSize_mm, ...
        xAutoRange_mm, yAutoRange_mm, ...
        overviewXRange_mm, overviewYRange_mm, ...
        scanTileSize_mm, ...
        temporaryFolder, v);

    %% Print summary
    nTileX = round(diff(xTissueRange_mm) / scanTileSize_mm);
    nTileY = round(diff(yTissueRange_mm) / scanTileSize_mm);
    fprintf('\nTissue Centroid: (%.2f, %.2f) mm\n', tissueCentroid_mm(1), tissueCentroid_mm(2));
    fprintf('Tissue Area:     %.2f mm^2\n', tissueArea_mm2);
    fprintf('Tiles: %d x %d = %d  (%g mm each)\n\n', nTileX, nTileY, nTileX*nTileY, scanTileSize_mm);
    fprintf('Detected Tissue Ranges (mm):\n\n');
    fprintf('  xOverall_mm = [%.2f  %.2f];\n', xTissueRange_mm(1), xTissueRange_mm(2));
    fprintf('  yOverall_mm = [%.2f  %.2f];\n\n', yTissueRange_mm(1), yTissueRange_mm(2));

    end % detectTissueScanRange

    % Inline helper to keep the figure visibility flag readable above.
    function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
    end

    % Tissue detection
    function tissue_mask = detectTissueMask(surfacePosition_mm, pixelSize_mm, v)
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
        warning('yOCTScanTissueOverview:noTissueAfterFiltering', ...
            'Tissue mask is empty. Try increasing DEPTH_FRACTION or reducing overviewZ_mm.');
    end

    if v
        fprintf('%s Detected tissue area: %.2f mm^2 (%.1f%% of overview).\n', ...
            datestr(now), sum(tissue_mask(:)) * pixelSize_mm^2, 100 * mean(tissue_mask(:)));
    end

    end % detectTissueMask

    % Render and save the summary figure (OCT en-face + tissue mask + detected
    % range + tile grid). PNG is always written; the figure is only shown on
    % screen when v=true.
    function saveScanRangeFigure( ...
        xTissueRange_mm, yTissueRange_mm, ...
        x_mm, y_mm, xySlice, tissue_mask, ...
        tissueCentroid_mm, tissueArea_mm2, pixelSize_mm, ...
        xAutoRange_mm, yAutoRange_mm, ...
        overviewXRange_mm, overviewYRange_mm, ...
        scanTileSize_mm, ...
        temporaryFolder, v)

    figureVisibility = ternary(v, 'on', 'off');
    fig = figure('Name', 'Tissue Overview - Accepted Scan Range', ...
        'Position', [150 150 1050 500], 'Visible', figureVisibility);

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
    title(ax1, sprintf('OCT en-face (XY) at %g µm/pixel  |  tissue area: %.2f mm\xB2', round(pixelSize_mm * 1e3), tissueArea_mm2));
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
    scanWidth_mm  = diff(xTissueRange_mm);
    scanHeight_mm = diff(yTissueRange_mm);
    title(ax2, sprintf('Tile grid: %d x %d = %d tiles  (%g mm each)  |  %.1f x %.1f mm', ...
        nTileX, nTileY, nTileX*nTileY, scanTileSize_mm, scanWidth_mm, scanHeight_mm));
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
    if ~v, close(fig); end

    end % saveScanRangeFigure
