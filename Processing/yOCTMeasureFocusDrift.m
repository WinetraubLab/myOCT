function focusPositionInImageZpix = yOCTMeasureFocusDrift( ...
    volumeOutputFolder, dispersionQuadraticTerm, varargin)
% Measure focus drift across a z-stack caused by refractive index mismatch
% (e.g. water objective imaging into cleared tissue). Manually click the
% focus on sampled tiles; returns a per-depth focus vector for yOCTProcessTiledScan.
%
% INPUTS:
%   volumeOutputFolder          - folder containing the scans and ScanInfo.json
%   dispersionQuadraticTerm     - dispersion correction value
%
% OPTIONAL PARAMETERS:
%
%   Parameter               Default
%
%   'focusMeasureStep_um'   50      Starting at the tissue surface / coverslip
%                                   interface (stage z = 0), measure the focus
%                                   every this many microns on one B-scan of
%                                   stage depth, going deeper. Shallower
%                                   (negative Z, air) scans are skipped. User can
%                                   stop measuring once the focus is not visible.
%   'outputDirectory'        ''      Where to save results (drift figure + focus vector)
%                               Three options:
%                                 (empty)         : save in volumeOutputFolder
%                                 'path/to/dir/'  : save in this dir given folder
%                                 'path/to/name'  : use name as filename base
%   'v'                     false   Verbose mode: prints progress and results,
%                                   and keeps the drift figure open.
%
% OUTPUT:
%   focusPositionInImageZpix:   1 x nDepths vector of focus pixels (one per zDepth scan
%                               in ScanInfo.json). Pass straight to yOCTProcessTiledScan
%                               as 'focusPositionInImageZpix'.

%% Parse inputs
p = inputParser;
addRequired(p, 'volumeOutputFolder', @ischar);
addRequired(p, 'dispersionQuadraticTerm', @isnumeric);
addParameter(p, 'focusMeasureStep_um', 50, @(x)(isnumeric(x) && isscalar(x) && x > 0));
addParameter(p, 'outputDirectory', '', @ischar);
addParameter(p, 'v', false, @islogical);
parse(p, volumeOutputFolder, dispersionQuadraticTerm, varargin{:});
in = p.Results;

volumeOutputFolder      = awsModifyPathForCompetability([in.volumeOutputFolder '/']);
dispersionQuadraticTerm = in.dispersionQuadraticTerm;
v                       = in.v;

%% Load scan geometry (z-depths, tile grid, single-tile dimensions)
geom = loadScanGeometry(volumeOutputFolder);

%% Choose which depths to measure (tissue surface/coverslip interface first, then deeper)
depthsToMeasure = selectDepthsToMeasure(geom.zDepths_mm, in.focusMeasureStep_um);

%% Measure the focus on each requested tile
measurements = measureFocus(geom, depthsToMeasure, dispersionQuadraticTerm, v);

%% Compute the focus for every depth
focusPositionInImageZpix = getFocusForAllDepths( ...
    measurements, geom.zDepths_mm, in.outputDirectory, volumeOutputFolder, v);

end % yOCTMeasureFocusDrift


%%  Helper functions
function geom = loadScanGeometry(volumeOutputFolder)
% Read ScanInfo.json and derive the geometry we need: z-depths, OCT system,
% single-tile dimensions, the tile-center grid, and the central tile:
json = awsReadJSON([volumeOutputFolder 'ScanInfo.json']);

zDepths_mm = json.zDepths(:)';
if length(zDepths_mm) < 2
    error('This scan has %d z-depth(s). A z-stack with multiple depths is required.', ...
        length(zDepths_mm));
end

if isfield(json, 'octSystem')
    octSystem = json.octSystem;
elseif isfield(json, 'OCTSystem')
    octSystem = json.OCTSystem;
else
    octSystem = '';
end

% Pass NaN so Z is NOT shifted to the focus: we want the raw tile z to click on:
[dimOneTile_mm, ~] = yOCTProcessTiledScan_createDimStructure(volumeOutputFolder, NaN);

if isfield(json, 'xCenters_mm'); xCenters = json.xCenters_mm; else; xCenters = json.xCenters; end
if isfield(json, 'yCenters_mm'); yCenters = json.yCenters_mm; else; yCenters = json.yCenters; end
[~, xi0] = min(abs(xCenters));
[~, yi0] = min(abs(yCenters));

geom = struct();
geom.volumeOutputFolder = volumeOutputFolder;
geom.json           = json;
geom.zDepths_mm     = zDepths_mm;
geom.octSystem      = octSystem;
geom.dimOneTile_mm  = dimOneTile_mm;
geom.xCenters       = xCenters;
geom.xi0            = xi0;                               % index of the central X tile
geom.yCenter0       = yCenters(yi0);                     % Y center to work on
geom.nYInTile       = length(dimOneTile_mm.y.values);
geom.yIInFileCenter = max(1, round(geom.nYInTile / 2));  % central Bscan
end


function measureSeq = selectDepthsToMeasure(zDepths_mm, focusMeasureStep_um)
% Choose z-depth indices to measure: start at z = 0 (tissue surface/coverslip interface) and
% step deeper every focusMeasureStep_um microns. Negative Z (gel) tiles are skipped:
[~, refIdx] = min(abs(zDepths_mm));
depthStep_mm = median(abs(diff(zDepths_mm)));
if depthStep_mm <= 0
    stride = 1;
else
    stride = max(1, round((focusMeasureStep_um * 1e-3) / depthStep_mm));
end
candidateIdx = find(zDepths_mm >= zDepths_mm(refIdx) - 1e-9);
[~, cOrder] = sort(zDepths_mm(candidateIdx));
candidateIdx = candidateIdx(cOrder);
measureSeq = candidateIdx(1:stride:end);

if isempty(measureSeq)
    error('No tiles selected to measure.');
end
end


function measurements = measureFocus(geom, depthsToMeasure, dispersionQuadraticTerm, v)
% Show each selected tile's B-scan and let the user select the focus. Returns a
% struct of the accepted focus positions with fields idx, focusPix, focusZmm (each a
% column vector, one entry per tile the user accepted).
if v
    fprintf('%s Measuring focus on %d tiles (z from %.3f to %.3f mm)\n', ...
        datestr(datetime), numel(depthsToMeasure), ...
        geom.zDepths_mm(depthsToMeasure(1)), geom.zDepths_mm(depthsToMeasure(end)));
end

hFig = figure('Name', 'Choose Focus Positions', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.15 0.12 0.62 0.78]);
h = createDiagnosticControls(hFig, geom.xCenters);

acceptedIdx      = [];
acceptedFocusPix = [];
acceptedFocusZmm = [];

% The X tile and Bscan the user settles on carry over to the next depth selection:
currentXTileI   = geom.xi0;
currentYIInFile = geom.yIInFileCenter;

for k = 1:numel(depthsToMeasure)
    zi = depthsToMeasure(k);
    zt = geom.zDepths_mm(zi);

    % Tile folder at this depth for next X tile (fall back to center):
    folderPath = findTileFolder(geom.json, geom.volumeOutputFolder, zt, ...
        geom.xCenters(currentXTileI), geom.yCenter0);
    if isempty(folderPath)
        folderPath = findTileFolder(geom.json, geom.volumeOutputFolder, zt, ...
            geom.xCenters(geom.xi0), geom.yCenter0);
        if isempty(folderPath)
            warning('No tile found for zDepth %.4f mm. Skipping.', zt);
            continue;
        end
        currentXTileI = geom.xi0;
    end

    % Assemble the per-tile state, hand it and wait for the user to choose:
    cursor = struct('folderPath', folderPath, ...
        'xTileI', currentXTileI, 'yIInFile', currentYIInFile, ...
        'zt', zt, 'k', k, 'nMeasure', numel(depthsToMeasure), ...
        'predPix', predictFocusPix(geom.zDepths_mm(acceptedIdx), acceptedFocusPix, zt));
    guidata(hFig, initTileState(geom, h, dispersionQuadraticTerm, cursor));

    renderTileBScan(hFig);
    uiwait(hFig);

    if ~ishandle(hFig)
        break; % user closed the window
    end
    state = guidata(hFig);

    % Carry the user's X-tile and Bscan choice over to the next depth selection:
    currentXTileI   = state.xTileI;
    currentYIInFile = state.yIInFile;

    if strcmp(state.action, 'stop')
        break;
    end
    if isnan(state.clickZpix)
        warning('No focus click registered for tile %d; skipping.', zi);
        continue;
    end

    acceptedIdx(end + 1)      = zi;               %#ok<AGROW>
    acceptedFocusPix(end + 1) = state.clickZpix;  %#ok<AGROW>
    acceptedFocusZmm(end + 1) = state.clickZmm;   %#ok<AGROW>

    updateDriftReadout(h.hDriftText, geom.zDepths_mm(acceptedIdx), ...
        acceptedFocusPix, state.dimFrame);
end

if ishandle(hFig)
    close(hFig);
end

measurements = struct('idx', acceptedIdx(:), ...
    'focusPix', acceptedFocusPix(:), 'focusZmm', acceptedFocusZmm(:));
end


function state = initTileState(geom, h, dispersionQuadraticTerm, cursor)
% Assemble the per-tile state struct holding the values that change each 
% iteration (folderPath, xTileI, yIInFile, zt, predPix, and the k/nMeasure 
% counters used for the title).
state = struct();

% What to reconstruct, and where it came from.
state.folderPath              = cursor.folderPath;
state.dimOneTile_mm           = geom.dimOneTile_mm;
state.octSystem               = geom.octSystem;
state.dispersionQuadraticTerm = dispersionQuadraticTerm;
state.json                    = geom.json;
state.volumeOutputFolder      = geom.volumeOutputFolder;

% Navigation position (sticky across depths)
state.yIInFile = cursor.yIInFile;
state.nYInTile = geom.nYInTile;
state.xCenters = geom.xCenters;
state.xTileI   = cursor.xTileI;
state.yCenter0 = geom.yCenter0;
state.zt       = cursor.zt;
state.predPix  = cursor.predPix;

state.titleStr = sprintf(['Depth %d of %d   (stage z = %.3f mm)\n' ...
    'Click the FOCUS then "Accept focus & Next".   ' ...
    'If you cannot see it: try another B-scan or X tile, or "Stop here".'], ...
    cursor.k, cursor.nMeasure, cursor.zt);

state.hAx         = h.hAx;
state.hBright     = h.hBright;
state.hContrast   = h.hContrast;
state.hBScanLabel = h.hBScanLabel;
state.hXTileLabel = h.hXTileLabel;

% Per-tile working values, filled in later:
state.dimFrame   = [];
state.baseLo     = 0;
state.baseHi     = 1;
state.clickZpix  = NaN;
state.clickZmm   = NaN;
state.hFocusLine = [];
state.action     = '';
end


function predPix = predictFocusPix(zStageAccepted_mm, focusPixAccepted, zt)
% Predicted focus pixel at depth zt from a running linear fit of the clicks so
% far (drawn as a blue guide). NaN until there are at least two points to fit:
if numel(focusPixAccepted) >= 2
    pcoef = polyfit(zStageAccepted_mm, focusPixAccepted, 1);
    predPix = round(polyval(pcoef, zt));
else
    predPix = NaN;
end
end


function updateDriftReadout(hDriftText, zStageAccepted_mm, focusPixAccepted, dimFrame)
% Update the live "drift so far" text in the window
n = numel(focusPixAccepted);
if n >= 2
    pc = polyfit(zStageAccepted_mm, focusPixAccepted, 1);
    dzpix_mm = median(diff(dimFrame.z.values));
    set(hDriftText, 'String', sprintf( ...
        'Clicked points: %d\nDrift slope: %.1f pix/mm\n= %.3f um/um', ...
        n, pc(1), pc(1) * dzpix_mm));
else
    set(hDriftText, 'String', sprintf( ...
        'Clicked points: %d\n(need >= 2 for slope)', n));
end
end


function focusPositionInImageZpix = getFocusForAllDepths( ...
    measurements, zDepths_mm, outputDirectory, volumeOutputFolder, v)
% Turn the accepted selections into (1) a per-tile table and (2) a focus pixel for
% every z-depth (linear interp, extrapolated at the ends). The vector is what
% yOCTProcessTiledScan consumes. Errors if nothing was chosen; prints the
% table when verbose.
if isempty(measurements.idx)
    error(['No focus measurements were recorded. The focus was not ' ...
        'visible/clickable on any tile.']);
end

% Per-tile table (one row per clicked tile):
measureIdx         = measurements.idx;
focusMeasured_pix  = measurements.focusPix;
focusMeasured_z_mm = measurements.focusZmm;

zStage_mm        = zDepths_mm(measureIdx); zStage_mm = zStage_mm(:);
drift_um         = (focusMeasured_z_mm - focusMeasured_z_mm(1)) * 1e3;
dStageFromRef_um = (zStage_mm - zStage_mm(1)) * 1e3;
driftPerStage    = drift_um ./ dStageFromRef_um;   % NaN on the reference row (0/0)

focusTable = table(measureIdx, zStage_mm, focusMeasured_pix, focusMeasured_z_mm, ...
    drift_um, dStageFromRef_um, driftPerStage, ...
    'VariableNames', {'tileIndex', 'zStage_mm', 'focusMeasured_pix', ...
    'focusMeasured_z_mm', 'drift_um', 'dStageFromRef_um', 'driftPerStage'});

% One focus pixel for every Z-depth.
if numel(measureIdx) >= 2
    focusPositionInImageZpix = interp1(zStage_mm, focusMeasured_pix, ...
        zDepths_mm(:), 'linear', 'extrap');
else
    focusPositionInImageZpix = focusMeasured_pix(1) * ones(numel(zDepths_mm), 1);
end
focusPositionInImageZpix = round(focusPositionInImageZpix(:)');

if v
    disp(focusTable);
end

generateFocusDiagnostic(outputDirectory, volumeOutputFolder, focusTable, ...
    focusPositionInImageZpix, zDepths_mm, v);
end


function generateFocusDiagnostic(outputDirectory, volumeOutputFolder, focusTable, ...
    focusPositionInImageZpix, zDepths_mm, v)
% Ggenerate the focus vector + table to file and the drift figure to .png. Resolves
% the output paths here (the only place that needs them). When v=true the drift
% figure stays open and the saved paths are printed; otherwise it is closed:
[matPath, figPath] = resolveOutputPaths(outputDirectory, volumeOutputFolder);

save(matPath, 'focusTable', 'focusPositionInImageZpix', 'zDepths_mm');

hPlot = plotFocusDrift(focusTable);
saveas(hPlot, figPath);
if ~v
    close(hPlot);
end

if v
    fprintf('%s Saved results to:\n  %s\n  %s\n', datestr(datetime), matPath, figPath);
end
end


function [matPath, figPath] = resolveOutputPaths(outputDirectory, defaultFolder)
% Resolve where to save the files from a user-supplied outputDirectory:
%   (empty)        : save in defaultFolder with the default filename
%   'path/to/dir/' : save in that folder with the default filename
%   'path/to/name' : use as file base: name.mat, name.png
DEFAULT_NAME = 'zChosenFocusPositions';
if isempty(outputDirectory)
    matPath = [defaultFolder DEFAULT_NAME '.mat'];
    figPath = [defaultFolder DEFAULT_NAME '.png'];
elseif outputDirectory(end) == '/' || outputDirectory(end) == '\' || isfolder(outputDirectory)
    folder = awsModifyPathForCompetability([outputDirectory '/']);
    matPath = [folder DEFAULT_NAME '.mat'];
    figPath = [folder DEFAULT_NAME '.png'];
else
    matPath = [outputDirectory '.mat'];
    figPath = [outputDirectory '.png'];
end
end


function hFig = plotFocusDrift(focusTable)
% Drift vs depth figure: measured points + least squares fit line
zStage_mm      = focusTable.zStage_mm;
drift_um       = focusTable.drift_um;
dStageFromRef_um = focusTable.dStageFromRef_um;

hFig = figure('Name', 'Focus drift vs depth', 'NumberTitle', 'off');
plot(zStage_mm * 1e3, drift_um, 'o', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0.2 0.4 0.9], 'MarkerEdgeColor', 'none');
grid on; hold on;
xlabel('Stage depth [\mum]');
ylabel('Focus drift in image [\mum]');
title('Focus drift vs stage depth');

if numel(zStage_mm) >= 2
    pfit = polyfit(dStageFromRef_um, drift_um, 1);
    yhat = polyval(pfit, dStageFromRef_um);
    ssres = sum((drift_um - yhat).^2);
    sstot = sum((drift_um - mean(drift_um)).^2);
    r2 = 1 - ssres / max(sstot, eps);
    plot(zStage_mm * 1e3, yhat, '-', 'Color', [0.85 0.2 0.2], 'LineWidth', 1.5);
    legend('Identified focus', 'Linear fit', 'Location', 'northwest');
    subtitle(sprintf('Least-squares drift slope ~ %.4f um/um  (R^2 = %.4f)', pfit(1), r2));
end
hold off;
end


function h = createDiagnosticControls(hFig, xCenters)
% Build window figure: Bscan axes, sliders, action and navigation buttons:
h.hAx = axes('Parent', hFig, 'Units', 'normalized', ...
    'Position', [0.10 0.32 0.86 0.60]);

uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.10 0.225 0.12 0.03], 'String', 'Brightness', ...
    'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
h.hBright = uicontrol(hFig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.23 0.225 0.40 0.03], 'Min', -1, 'Max', 1, 'Value', -0.2, ...
    'Callback', @onAdjustDisplay);

uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.10 0.175 0.12 0.03], 'String', 'Contrast', ...
    'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
h.hContrast = uicontrol(hFig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.23 0.175 0.40 0.03], 'Min', 0.3, 'Max', 3, 'Value', 1.5, ...
    'Callback', @onAdjustDisplay);

h.hDriftText = uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.66 0.155 0.30 0.085], ...
    'String', 'Drift so far: need >= 2 clicked points', ...
    'HorizontalAlignment', 'left', 'BackgroundColor', 'w', 'FontSize', 10);

uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.10 0.025 0.24 0.055], 'String', 'Accept focus & Next', ...
    'FontSize', 11, 'Callback', @onAcceptNext);
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.36 0.025 0.28 0.055], 'String', 'Can''t see focus - Stop here', ...
    'FontSize', 11, 'Callback', @onStop);

uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.10 0.095 0.095 0.05], 'String', '< B-scan', ...
    'FontSize', 10, 'Callback', {@onOtherBScan, -1});
h.hBScanLabel = uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.20 0.095 0.125 0.04], 'String', 'B-scan', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'FontSize', 9);
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.33 0.095 0.095 0.05], 'String', 'B-scan >', ...
    'FontSize', 10, 'Callback', {@onOtherBScan, +1});

xTileEnable = 'on';
if length(xCenters) <= 1; xTileEnable = 'off'; end
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.50 0.095 0.095 0.05], 'String', '< X tile', ...
    'FontSize', 10, 'Enable', xTileEnable, 'Callback', {@onOtherXTile, -1});
h.hXTileLabel = uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.60 0.095 0.125 0.04], 'String', 'X tile', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'FontSize', 9);
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.73 0.095 0.095 0.05], 'String', 'X tile >', ...
    'FontSize', 10, 'Enable', xTileEnable, 'Callback', {@onOtherXTile, +1});
end


function [scan1, dimFrame] = reconstructCenterBScan( ...
    folderPath, dimOneTile_mm, yIInFile, octSystem, dispersionQuadraticTerm, json)
% Reconstruct one Bscan of one tile exactly the way yOCTProcessTiledScan
% does for selection:
reconstructConfig = {'dispersionQuadraticTerm', dispersionQuadraticTerm};
[intFrame, dimFrame] = yOCTLoadInterfFromFile([{folderPath}, reconstructConfig, ...
    {'dimensions', dimOneTile_mm, 'YFramesToProcess', yIInFile, 'octSystem', octSystem}]);
[scan1, ~] = yOCTInterfToScanCpx([{intFrame} {dimFrame} reconstructConfig]);
scan1 = abs(scan1);
for i = ndims(scan1):-1:3
    scan1 = squeeze(mean(scan1, i));
end
if isfield(json.octProbe, 'OpticalPathCorrectionPolynomial')
    [scan1, ~] = yOCTOpticalPathCorrection(scan1, dimFrame, json);
end
end


function onAdjustDisplay(src, ~)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
if isempty(st) || ~isfield(st, 'hAx'); return; end
b = get(st.hBright,   'Value');
c = get(st.hContrast, 'Value');
baseCenter = 0.5 * (st.baseLo + st.baseHi);
baseWidth  = st.baseHi - st.baseLo;
width  = baseWidth / c;
center = baseCenter - b * 0.5 * baseWidth;
lo = center - 0.5 * width;
hi = center + 0.5 * width;
if hi <= lo; hi = lo + eps; end
set(st.hAx, 'CLim', [lo hi]);
end


function onClickFocus(src, ~)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
cp = get(st.hAx, 'CurrentPoint');
zClick = cp(1, 2);
[~, pix] = min(abs(zClick - st.dimFrame.z.values));
st.clickZpix = pix;
st.clickZmm  = st.dimFrame.z.values(pix);
if isempty(st.hFocusLine) || ~ishandle(st.hFocusLine)
    hold(st.hAx, 'on');
    st.hFocusLine = plot(st.hAx, st.dimFrame.x.values([1 end]), ...
        st.clickZmm * [1 1], '-', 'Color', [0.95 0.85 0.15], ...
        'LineWidth', 2, 'HitTest', 'off', 'PickableParts', 'none');
    hold(st.hAx, 'off');
else
    set(st.hFocusLine, 'YData', st.clickZmm * [1 1]);
end
guidata(hFig, st);
end


function onAcceptNext(src, ~)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
st.action = 'next';
guidata(hFig, st);
uiresume(hFig);
end


function onStop(src, ~)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
st.action = 'stop';
guidata(hFig, st);
uiresume(hFig);
end


function renderTileBScan(hFig)
% Reconstruct and draw the current Bscan of the active tile. Called once per
% tile and again on every Bscan / Xtile navigation step:
st = guidata(hFig);

[scan1, dimFrame] = reconstructCenterBScan( ...
    st.folderPath, st.dimOneTile_mm, st.yIInFile, st.octSystem, ...
    st.dispersionQuadraticTerm, st.json);

imLog = mag2db(abs(scan1) + eps);
st.dimFrame = dimFrame;
st.baseLo   = prctile(imLog(:), 5);
st.baseHi   = prctile(imLog(:), 99.8);
if st.baseHi <= st.baseLo; st.baseHi = st.baseLo + 1; end

cla(st.hAx);
hImg = imagesc(st.hAx, dimFrame.x.values, dimFrame.z.values, imLog);
colormap(st.hAx, gray);
axis(st.hAx, 'tight');
xlabel(st.hAx, 'x [mm]');
ylabel(st.hAx, 'z [mm]  (absolute tile depth)');
title(st.hAx, st.titleStr, 'Interpreter', 'none');
set(hImg, 'ButtonDownFcn', @onClickFocus);

% Blue dashed guide from the running drift fit.
if isfield(st, 'predPix') && ~isnan(st.predPix) ...
        && st.predPix >= 1 && st.predPix <= length(dimFrame.z.values)
    hold(st.hAx, 'on');
    plot(st.hAx, dimFrame.x.values([1 end]), ...
        dimFrame.z.values(round(st.predPix)) * [1 1], '--', ...
        'Color', [0.3 0.8 1.0], 'LineWidth', 1.0, ...
        'HitTest', 'off', 'PickableParts', 'none');
    hold(st.hAx, 'off');
end

% Yellow line for a previous click (carries over when stepping B-scans).
st.hFocusLine = [];
if isfield(st, 'clickZmm') && ~isnan(st.clickZmm)
    hold(st.hAx, 'on');
    st.hFocusLine = plot(st.hAx, dimFrame.x.values([1 end]), ...
        st.clickZmm * [1 1], '-', 'Color', [0.95 0.85 0.15], ...
        'LineWidth', 2, 'HitTest', 'off', 'PickableParts', 'none');
    hold(st.hAx, 'off');
end

if isfield(st, 'hBScanLabel') && ishandle(st.hBScanLabel)
    set(st.hBScanLabel, 'String', sprintf('B-scan %d / %d', st.yIInFile, st.nYInTile));
end
if isfield(st, 'hXTileLabel') && ishandle(st.hXTileLabel)
    set(st.hXTileLabel, 'String', sprintf('X tile %d / %d', st.xTileI, length(st.xCenters)));
end

guidata(hFig, st);
onAdjustDisplay(st.hBright, []);
end


function onOtherBScan(src, ~, delta)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
newY = max(1, min(st.nYInTile, st.yIInFile + delta));
if newY == st.yIInFile; return; end
st.yIInFile = newY;
guidata(hFig, st);
renderTileBScan(hFig);
end


function onOtherXTile(src, ~, delta)
hFig = ancestor(src, 'figure');
st = guidata(hFig);
newXTileI = max(1, min(length(st.xCenters), st.xTileI + delta));
if newXTileI == st.xTileI; return; end
newFolder = findTileFolder(st.json, st.volumeOutputFolder, st.zt, ...
    st.xCenters(newXTileI), st.yCenter0);
if isempty(newFolder)
    warning('No tile at this depth for X tile %d; staying on tile %d.', ...
        newXTileI, st.xTileI);
    return;
end
st.xTileI   = newXTileI;
st.folderPath = newFolder;
guidata(hFig, st);
renderTileBScan(hFig);
end


function folderPath = findTileFolder(json, volumeOutputFolder, zt, xc, yc)
folderIdx = find( ...
    abs(json.gridZcc - zt) < 1e-9 & ...
    abs(json.gridXcc - xc) < 1e-9 & ...
    abs(json.gridYcc - yc) < 1e-9, 1);
if isempty(folderIdx)
    folderPath = '';
    return;
end
folderPath = awsModifyPathForCompetability( ...
    [volumeOutputFolder '/' json.octFolders{folderIdx} '/']);
end
