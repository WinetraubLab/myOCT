function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm] = yOCTScanTissueOverview(varargin)
% yOCTScanTissueOverview performs a low-resolution OCT overview scan, detects the tissue
% footprint, and provides overview with suggested scan ranges.
%
% PIPELINE:
%   1. Scan overview tiles at a fixed Z depth with yOCTScanTile
%   2. Process scanned tiles to reconstruct volume with yOCTProcessTiledScan
%   3. Load processed volume with yOCTFromTif and detect tissue surface with yOCTFindTissueSurface
%   4. Detect tissue footprint and compute tile-aligned scan ranges
%   5. Request user review for range refinement (if requestRefinement=true)
%   6. Provide tissue overview with confirmed ranges as output
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
%   requestRefinement       false       If true, ask the user to review and adjust the detected
%                                       tissue range before accepting. If false, the auto-detected range
%                                       is used directly.
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
addParameter(p, 'requestRefinement',         false,  @islogical);

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
requestRefinement        = in.requestRefinement;

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
        return;
    end
    % Validate everything before touching hardware
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
    xRange_mm, yRange_mm, requestRefinement, v);

end % main function


%% LOCAL FUNCTIONS
%  Analyze overview volume: detect tissue and compute scan ranges
function [xTissueRange_mm, yTissueRange_mm, tissueCentroid_mm] = i_analyzeVolumeAndGetRanges( ...
    overviewProcessedTif, analyzeTifOnly, preloadedScanPath, ...
    overviewZ_um, scanTileSize_mm, pixelSize_um, temporaryFolder, ...
    xRange_mm, yRange_mm, requestRefinement, v)

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
    error('yOCTScanTissueOverview:noTissueDetected', ...
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
xAutoRange_mm = [max(xAutoRange_mm(1), xRange_mm(1)),  min(xAutoRange_mm(2), xRange_mm(2))];
yAutoRange_mm = [max(yAutoRange_mm(1), yRange_mm(1)),  min(yAutoRange_mm(2), yRange_mm(2))];

% Accept scan range (requestRefinement=true) or use auto directly (requestRefinement=false)
if ~requestRefinement
    xTissueRange_mm = xAutoRange_mm;
    yTissueRange_mm = yAutoRange_mm;
else
    [xTissueRange_mm, yTissueRange_mm] = i_showOverviewUI( ...
        surfacePosition_mm, x_mm_row, y_mm_col, ...
        xySlice, tissue_mask, ...
        tissueCentroid_mm, tissueWidth_mm, tissueHeight_mm, ...
        xAutoRange_mm, yAutoRange_mm, ...
        xRange_mm, yRange_mm, ...
        scanTileSize_mm);
end

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

% Show user refinement window to review detected tissue and adjust scan range before accepting
function [xTissueRange_mm, yTissueRange_mm] = i_showOverviewUI( ...
    surfacePosition_mm, x_mm, y_mm, ...
    xySlice, tissue_mask, ...
    tissueCentroid_mm, tissueWidth_mm, tissueHeight_mm, ...
    xAutoRange_mm, yAutoRange_mm, ...
    overviewXRange_mm, overviewYRange_mm, ...
    scanTileSize_mm)

% State
state.xRange         = xAutoRange_mm;
state.yRange         = yAutoRange_mm;
state.viewMode       = 'oct';   % 'oct' | 'heatmap' are optional modes
state.accepted       = false;
state.showTissueMask = true;
state.outOfBounds    = false;   % true when accepted range exceeds overview scan area

% Color limits
validSurf = surfacePosition_mm(~isnan(surfacePosition_mm) & tissue_mask);
if isempty(validSurf), validSurf = surfacePosition_mm(~isnan(surfacePosition_mm)); end
if isempty(validSurf)
    heatmapClim = [0 1];
else
    heatmapClim = prctile(validSurf, [2 98]);
    if heatmapClim(1) >= heatmapClim(2), heatmapClim(2) = heatmapClim(1) + 0.001; end
end
octClim = prctile(xySlice(:), [1 99]);
if octClim(1) >= octClim(2), octClim(2) = octClim(1) + 0.001; end

% Figure
fig = uifigure('Name', 'Tissue Overview - Review Scan Range', ...
    'Position', [100 100 1100 840], ...
    'CloseRequestFcn', @(src,evt) onClose(src));

mainGrid = uigridlayout(fig, [4, 2]);
mainGrid.RowHeight   = {'1x', '1x', 50, 230};
mainGrid.ColumnWidth = {'1x', '1x'};

axImage = uiaxes(mainGrid);
axImage.Layout.Row = [1 2]; axImage.Layout.Column = 1;
xlabel(axImage, 'X (mm)'); ylabel(axImage, 'Y (mm)');
axis(axImage, 'equal'); axImage.XDir = 'normal'; axImage.YDir = 'normal';
axImage.Interactions = [];

axGrid = uiaxes(mainGrid);
axGrid.Layout.Row = [1 2]; axGrid.Layout.Column = 2;
xlabel(axGrid, 'X (mm)'); ylabel(axGrid, 'Y (mm)');
title(axGrid, 'Proposed Tile Grid');
axis(axGrid, 'equal'); axGrid.XDir = 'normal'; axGrid.YDir = 'normal';
axGrid.Interactions = [];

axLegend = uiaxes(mainGrid);
axLegend.Layout.Row = 3; axLegend.Layout.Column = [1 2];
axLegend.Visible = 'off';

ctrlPanel = uipanel(mainGrid, 'Title', 'Controls');
ctrlPanel.Layout.Row = 4; ctrlPanel.Layout.Column = [1 2];

ctrlGrid = uigridlayout(ctrlPanel, [5 7]);
ctrlGrid.RowHeight   = {32, 32, 32, 32, 36};
ctrlGrid.ColumnWidth = {130, 90, 28, 90, '1x', 160, 130};
ctrlGrid.Padding     = [8 6 8 6];
ctrlGrid.RowSpacing  = 4;

% Row 1: Preview label + dropdown
lblPreview = uilabel(ctrlGrid, 'Text', 'Preview:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
lblPreview.Layout.Row = 1; lblPreview.Layout.Column = 1;
ddView = uidropdown(ctrlGrid, ...
    'Items', {'OCT en-face (XY)', 'Surface depth heatmap'}, ...
    'Value', 'OCT en-face (XY)', ...
    'ValueChangedFcn', @(dd,~) onViewChange(dd.Value));
ddView.Layout.Row = 1; ddView.Layout.Column = [2 4];

% Col 5: Current Range display - title row 1, X+Y tightly packed in rows 2-3
lblFinalTitle = uilabel(ctrlGrid, 'Text', 'Current Range:', ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 15);
lblFinalTitle.Layout.Row = 1; lblFinalTitle.Layout.Column = 5;

finalRangePanel = uipanel(ctrlGrid, 'BorderType', 'none');
finalRangePanel.Layout.Row = [2 3]; finalRangePanel.Layout.Column = 5;
finalRangeGrid = uigridlayout(finalRangePanel, [2 1]);
finalRangeGrid.RowHeight   = {'1x', '1x'};
finalRangeGrid.ColumnWidth = {'1x'};
finalRangeGrid.Padding     = [0 0 0 0];
finalRangeGrid.RowSpacing  = 0;

lblFinalX = uilabel(finalRangeGrid, 'Text', '', ...
    'FontName', 'Courier New', 'FontSize', 15, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right', 'FontColor', [0.1 0.6 0.1]);
lblFinalX.Layout.Row = 1; lblFinalX.Layout.Column = 1;

lblFinalY = uilabel(finalRangeGrid, 'Text', '', ...
    'FontName', 'Courier New', 'FontSize', 15, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right', 'FontColor', [0.1 0.6 0.1]);
lblFinalY.Layout.Row = 2; lblFinalY.Layout.Column = 1;

% Row 2: X range
lblXRange = uilabel(ctrlGrid, 'Text', 'X range (mm):', 'HorizontalAlignment', 'right');
lblXRange.Layout.Row = 2; lblXRange.Layout.Column = 1;
efXMin = uieditfield(ctrlGrid, 'numeric', 'Value', xAutoRange_mm(1), ...
    'ValueChangedFcn', @(ef,evt) onRangeEdit('xmin', ef.Value));
efXMin.Layout.Row = 2; efXMin.Layout.Column = 2;
lblXSep = uilabel(ctrlGrid, 'Text', 'to', 'HorizontalAlignment', 'center');
lblXSep.Layout.Row = 2; lblXSep.Layout.Column = 3;
efXMax = uieditfield(ctrlGrid, 'numeric', 'Value', xAutoRange_mm(2), ...
    'ValueChangedFcn', @(ef,evt) onRangeEdit('xmax', ef.Value));
efXMax.Layout.Row = 2; efXMax.Layout.Column = 4;

% Row 3: Y range
lblYRange = uilabel(ctrlGrid, 'Text', 'Y range (mm):', 'HorizontalAlignment', 'right');
lblYRange.Layout.Row = 3; lblYRange.Layout.Column = 1;
efYMin = uieditfield(ctrlGrid, 'numeric', 'Value', yAutoRange_mm(1), ...
    'ValueChangedFcn', @(ef,evt) onRangeEdit('ymin', ef.Value));
efYMin.Layout.Row = 3; efYMin.Layout.Column = 2;
lblYSep = uilabel(ctrlGrid, 'Text', 'to', 'HorizontalAlignment', 'center');
lblYSep.Layout.Row = 3; lblYSep.Layout.Column = 3;
efYMax = uieditfield(ctrlGrid, 'numeric', 'Value', yAutoRange_mm(2), ...
    'ValueChangedFcn', @(ef,evt) onRangeEdit('ymax', ef.Value));
efYMax.Layout.Row = 3; efYMax.Layout.Column = 4;

% Row 4: Info label (cols 1-5)
lblInfo = uilabel(ctrlGrid, 'Text', '...', 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
lblInfo.Layout.Row = 4; lblInfo.Layout.Column = [1 5];

% Row 5: Copy-paste bar (full width cols 1-5)
efCopyPaste = uieditfield(ctrlGrid, 'text', 'Value', '', 'Editable', 'off', ...
    'FontName', 'Courier New', 'FontSize', 13, ...
    'Tooltip', 'Click then Ctrl+A, Ctrl+C to copy');
efCopyPaste.Layout.Row = 5; efCopyPaste.Layout.Column = [1 5];

% Right panel: Accept Range + Reset (col 6-7, rows 1-5)
rightPanel = uipanel(ctrlGrid, 'BorderType', 'none');
rightPanel.Layout.Row = [1 5]; rightPanel.Layout.Column = [6 7];
rightGrid = uigridlayout(rightPanel, [2 1]);
rightGrid.RowHeight   = {'1x', 32};
rightGrid.ColumnWidth = {'1x'};
rightGrid.Padding     = [4 4 4 4];
rightGrid.RowSpacing  = 6;

btnAccept = uibutton(rightGrid, 'Text', 'Accept Range', ...
    'ButtonPushedFcn', @(btn,evt) onAccept(), ...
    'BackgroundColor', [0.2 0.7 0.2], 'FontColor', [1 1 1], 'FontWeight', 'bold', 'FontSize', 16);
btnAccept.Layout.Row = 1; btnAccept.Layout.Column = 1;

btnReset = uibutton(rightGrid, 'Text', 'Reset', 'ButtonPushedFcn', @(btn,evt) onReset());
btnReset.Layout.Row = 2; btnReset.Layout.Column = 1;

redrawAll();

try
    uiwait(fig);
catch
    if isvalid(fig), delete(fig); end
    error('yOCTScanTissueOverview:userInterrupted', ...
        'Overview window interrupted. Re-run when ready.');
end

if ~isvalid(fig)
    error('yOCTScanTissueOverview:windowClosedByUser', ...
        'Overview window closed before accepting a range.');
end

xTissueRange_mm = state.xRange;
yTissueRange_mm = state.yRange;
delete(fig);

    % Callbacks

    function onViewChange(selectedItem)
        if contains(selectedItem, 'heatmap', 'IgnoreCase', true)
            state.viewMode = 'heatmap';
        else
            state.viewMode = 'oct';
        end
        redrawImagePanel();
    end

    function onRangeEdit(which, val)
        % The edited end stays exactly as typed.
        % The companion end moves the minimum amount so that span is a
        % multiple of scanTileSize_mm (rounded to nearest tile multiple).
        switch which
            case 'xmin'
                rawSpan = state.xRange(2) - val;
                snappedSpan = max(scanTileSize_mm, round(rawSpan / scanTileSize_mm) * scanTileSize_mm);
                newMax = round((val + snappedSpan) * 100) / 100;
                state.xRange = [val, newMax];
                efXMin.Value = val; efXMax.Value = newMax;
            case 'xmax'
                rawSpan = val - state.xRange(1);
                snappedSpan = max(scanTileSize_mm, round(rawSpan / scanTileSize_mm) * scanTileSize_mm);
                newMin = round((val - snappedSpan) * 100) / 100;
                state.xRange = [newMin, val];
                efXMin.Value = newMin; efXMax.Value = val;
            case 'ymin'
                rawSpan = state.yRange(2) - val;
                snappedSpan = max(scanTileSize_mm, round(rawSpan / scanTileSize_mm) * scanTileSize_mm);
                newMax = round((val + snappedSpan) * 100) / 100;
                state.yRange = [val, newMax];
                efYMin.Value = val; efYMax.Value = newMax;
            case 'ymax'
                rawSpan = val - state.yRange(1);
                snappedSpan = max(scanTileSize_mm, round(rawSpan / scanTileSize_mm) * scanTileSize_mm);
                newMin = round((val - snappedSpan) * 100) / 100;
                state.yRange = [newMin, val];
                efYMin.Value = newMin; efYMax.Value = val;
        end

        % Check if range exceeds overview scan boundary
        state.outOfBounds = ...
            state.xRange(1) < overviewXRange_mm(1) || state.xRange(2) > overviewXRange_mm(2) || ...
            state.yRange(1) < overviewYRange_mm(1) || state.yRange(2) > overviewYRange_mm(2);

        redrawAll();
    end

    function onLegendClick(~, evt)
        if strcmp(evt.Target.DisplayName, 'Tissue mask')
            state.showTissueMask = ~state.showTissueMask;
            redrawImagePanel();
        end
    end

    function onAccept()
        state.accepted = true;
        uiresume(fig);
    end

    function onReset()
        state.xRange = xAutoRange_mm;
        state.yRange = yAutoRange_mm;
        state.outOfBounds = false;
        efXMin.Value = xAutoRange_mm(1);
        efXMax.Value = xAutoRange_mm(2);
        efYMin.Value = yAutoRange_mm(1);
        efYMax.Value = yAutoRange_mm(2);
        redrawAll();
    end

    function onClose(src)
        delete(src);
    end

    % Drawing helpers

    function redrawAll()
        redrawImagePanel();
        redrawGridPanel();
        redrawLegendPanel();
        updateInfoLabel();
    end

    function redrawImagePanel()
        cla(axImage);
        hold(axImage, 'on');

        if strcmp(state.viewMode, 'heatmap')
            surfDisplay = surfacePosition_mm;
            surfDisplay(isnan(surfDisplay)) = heatmapClim(1);
            hImg = imagesc(axImage, x_mm, y_mm, surfDisplay);
            set(hImg, 'AlphaData', 0.25 + 0.75*double(tissue_mask));
            colormap(axImage, 'turbo');
            clim(axImage, heatmapClim);
            cb = colorbar(axImage);
            cb.Label.String = 'Surface depth (mm)';
            title(axImage, 'Surface heatmap (bright = detected tissue)');
        else
            imagesc(axImage, x_mm, y_mm, xySlice);
            colormap(axImage, 'gray');
            clim(axImage, octClim);
            if state.showTissueMask
                tissueMaskRGB = cat(3, zeros(size(tissue_mask)), ones(size(tissue_mask)), zeros(size(tissue_mask)));
                hMaskImg = imagesc(axImage, x_mm, y_mm, tissueMaskRGB);
                set(hMaskImg, 'AlphaData', 0.3*double(tissue_mask));
            end
            title(axImage, 'OCT en-face (XY) + Tissue Mask');
        end

        hMaskProxy = fill(axImage, NaN, NaN, [0 0.85 0], ...
            'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', 'Tissue mask');
        if ~state.showTissueMask, hMaskProxy.Visible = 'off'; end

        xT = [xAutoRange_mm(1) xAutoRange_mm(2) xAutoRange_mm(2) xAutoRange_mm(1) xAutoRange_mm(1)];
        yT = [yAutoRange_mm(1) yAutoRange_mm(1) yAutoRange_mm(2) yAutoRange_mm(2) yAutoRange_mm(1)];
        plot(axImage, xT, yT, '--c', 'LineWidth', 1, 'DisplayName', 'Detected Range');

        xR = [state.xRange(1) state.xRange(2) state.xRange(2) state.xRange(1) state.xRange(1)];
        yR = [state.yRange(1) state.yRange(1) state.yRange(2) state.yRange(2) state.yRange(1)];
        plot(axImage, xR, yR, '-y', 'LineWidth', 2.5, 'DisplayName', 'Current Range');
        if state.outOfBounds
            % Overlay red dots to signal out-of-bounds
            plot(axImage, xR, yR, ':r', 'LineWidth', 2.5, 'HandleVisibility', 'off');
        end

        plot(axImage, 0, 0, 'r.', 'MarkerSize', 18, 'DisplayName', 'Stage Origin');
        plot(axImage, tissueCentroid_mm(1), tissueCentroid_mm(2), 'm+', ...
            'MarkerSize', 14, 'LineWidth', 2, 'DisplayName', 'Tissue Centroid');

        legend(axImage, 'off');
        axis(axImage, 'equal', 'tight');
        xlim(axImage, overviewXRange_mm + [-0.1 0.1]);
        ylim(axImage, overviewYRange_mm + [-0.1 0.1]);
        hold(axImage, 'off');
    end

    function redrawGridPanel()
        cla(axGrid);
        hold(axGrid, 'on');

        xEdges = state.xRange(1) : scanTileSize_mm : state.xRange(2);
        yEdges = state.yRange(1) : scanTileSize_mm : state.yRange(2);

        for xi = 1:length(xEdges)
            plot(axGrid, [xEdges(xi) xEdges(xi)], state.yRange, '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
        end
        for yi = 1:length(yEdges)
            plot(axGrid, state.xRange, [yEdges(yi) yEdges(yi)], '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
        end

        for xi = 1:length(xEdges)-1
            for yi = 1:length(yEdges)-1
                fill(axGrid, ...
                    [xEdges(xi) xEdges(xi+1) xEdges(xi+1) xEdges(xi)], ...
                    [yEdges(yi) yEdges(yi) yEdges(yi+1) yEdges(yi+1)], ...
                    [0.75 0.85 1.0], 'EdgeColor', [0.5 0.5 0.8], 'LineWidth', 0.5);
            end
        end

        xR = [state.xRange(1) state.xRange(2) state.xRange(2) state.xRange(1) state.xRange(1)];
        yR = [state.yRange(1) state.yRange(1) state.yRange(2) state.yRange(2) state.yRange(1)];
        xT = [xAutoRange_mm(1) xAutoRange_mm(2) xAutoRange_mm(2) xAutoRange_mm(1) xAutoRange_mm(1)];
        yT = [yAutoRange_mm(1) yAutoRange_mm(1) yAutoRange_mm(2) yAutoRange_mm(2) yAutoRange_mm(1)];
        plot(axGrid, xT, yT, '--c', 'LineWidth', 1);
        plot(axGrid, xR, yR, '-y', 'LineWidth', 2.5);
        plot(axGrid, 0, 0, 'r.', 'MarkerSize', 18);
        plot(axGrid, tissueCentroid_mm(1), tissueCentroid_mm(2), 'm+', 'MarkerSize', 14, 'LineWidth', 2);
        legend(axGrid, 'off');

        axis(axGrid, 'equal', 'tight');
        xlim(axGrid, overviewXRange_mm + [-0.1 0.1]);
        ylim(axGrid, overviewYRange_mm + [-0.1 0.1]);
        hold(axGrid, 'off');
    end

    function redrawLegendPanel()
        cla(axLegend);
        hold(axLegend, 'on');
        hL1 = plot(axLegend, NaN, NaN, '--c', 'LineWidth', 1,   'DisplayName', 'Detected Range');
        hL2 = plot(axLegend, NaN, NaN, '-y',  'LineWidth', 2.5, 'DisplayName', 'Current Range');
        hLm = fill(axLegend, NaN, NaN, [0 0.85 0], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', 'Tissue Mask');
        hL3 = plot(axLegend, NaN, NaN, 'r.', 'MarkerSize', 18, 'DisplayName', 'Stage Origin');
        hL4 = plot(axLegend, NaN, NaN, 'm+', 'MarkerSize', 14, 'LineWidth', 2, 'DisplayName', ...
            sprintf('Tissue Centroid (%.2f, %.2f)', tissueCentroid_mm(1), tissueCentroid_mm(2)));
        hold(axLegend, 'off');
        legend(axLegend, [hL1, hL2, hLm, hL3, hL4], 'Orientation', 'horizontal', 'Location', 'north', 'FontSize', 11);
    end

    function updateInfoLabel()
        nTileX = round(diff(state.xRange) / scanTileSize_mm);
        nTileY = round(diff(state.yRange) / scanTileSize_mm);
        infoStr = sprintf( ...
            'Tissue: %.2f x %.2f mm  |  Tile: %g mm  |  Tiles: %d x %d = %d  |  Scan: %.2f x %.2f mm', ...
            tissueWidth_mm, tissueHeight_mm, scanTileSize_mm, ...
            nTileX, nTileY, nTileX*nTileY, diff(state.xRange), diff(state.yRange));
        lblFinalX.Text = sprintf('X = [%g  %g]', state.xRange(1), state.xRange(2));
        lblFinalY.Text = sprintf('Y = [%g  %g]', state.yRange(1), state.yRange(2));
        efCopyPaste.Value = sprintf('xOverall_mm = [%g %g];    yOverall_mm = [%g %g];', ...
            state.xRange(1), state.xRange(2), state.yRange(1), state.yRange(2));
        if state.outOfBounds
            lblInfo.Text = ['WARNING: Range exceeds overview scan area. Lens may collide with the cassette!  |  ' infoStr];
            lblInfo.FontColor    = [0.85 0 0];
            lblFinalTitle.FontColor = [0.85 0 0];
            lblFinalX.FontColor  = [0.85 0 0];
            lblFinalY.FontColor  = [0.85 0 0];
            btnAccept.BackgroundColor = [0.85 0.1 0.1];
        else
            lblInfo.Text = infoStr;
            lblInfo.FontColor    = [0 0 0];
            lblFinalTitle.FontColor = [0 0 0];
            lblFinalX.FontColor  = [0.1 0.6 0.1];
            lblFinalY.FontColor  = [0.1 0.6 0.1];
            btnAccept.BackgroundColor = [0.2 0.7 0.2];
        end
    end

end % i_showOverviewUI

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
    warning('yOCTScanTissueOverview:noTissueAfterFiltering', ...
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
