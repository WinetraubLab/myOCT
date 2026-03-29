% Demo OCT Multi Coordinate Scan
% Run this script to perform OCT scans at different XY coordinates, supporting
% overlap between tiles. It follows our global coordinate system here:
% https://docs.google.com/presentation/d/1tOod76WvhvOuByo-K81YB4b3QjRq-6A5j2ztS_ANSNo
%
% Features:
% - roiSize_mm : ROI size in mm as [X Y]. Example: [2 1] -> X=[-1,1], Y=[-0.5,0.5].
% - overlapXY  : Overlap fraction [X Y], where 0 = no overlap, 0.5 = 50%.
%                   Example: [0.5 0.5] = 50% overlap in both axes.
%
% Modes (how scans are chosen):
% 1. Auto-grid (ROI tiling) -> default
%    Set roiSize_mm = [X Y] and overlapXY = [x y].
%     The script will convert it to coordCenters_mm = [xMin xMax yMin yMax] and 
%       build a grid to tile the ROI. Step comes from FOV and overlap.
%
% 2. Explicit centers (manual points)
%    Provide coordCenters_mm as an Nx2 list of [x y] in mm, for example:
%        coordCenters_mm = [0 0; 1 0; 0 1; -1 0; 0 -1];
%    This will ignore ROI/overlap. Only these points are scanned. (The origin [0 0] is always 
%       added first automatically).
%
% *Use only ONE mode at a time.
%
% Both modes will:
% - Always scan the origin [0 0] as the first tile, even if not requested.
% - Visual coverage preview heatmap, highlighting overlap regions (2x, 3x).
% - Name individual folders with their corresponding scan coordinates "[x, y]".
yOCTSetLibraryPath();                                        

%% INPUTS

outputFolder = '.\';  % Folder path where to save files

pixelSize_um        = 1;        % Pixel size in XY (microns)
octProbePath        = yOCTGetProbeIniPath('40x','OCTP900');
octProbeFOV_mm      = 0.5;      % Field of view (mm): 0.5 (40x) | 1.0 (10x)

xOverall_mm         = [-0.25 0.25];  % Single-tile size in X (mm)
yOverall_mm         = [-0.25 0.25];  % Single-tile size in Y (mm)

% Entire area ROI (must be multiple of FOV)
roiSize_mm = [2 2];     % ROI size [X Y] in mm. Example: [2 1] -> X=[-1,1], Y=[-0.5,0.5]
overlapXY  = [0.5 0.5]; % Overlap fraction [X Y]. Example: [0.5 0.5] = 50% overlap in both directions

% Z-depth scan parameters
scanZJump_um        = 5;        % 5 microns (40x) | 15 microns (10x)
zToScan_mm = unique([-100 (-30:scanZJump_um:200), 0])*1e-3;
focusSigma          = 10;       % 10 px (40x) | 20 px (10x)

tissueRefractiveIdx  = 1.33;    % 1.33 (water) or 1.4 (oil)
oct2stageXYAngleDeg  = 0;       % angle between Galvo X & motor X

% Dispersion/focus calibration (if empty, it will be estimated automatically once)
dispersionQuadraticTerm  = [];   
focusPositionInImageZpix = [];      

% Flags
skipScanning   = true;    % true = Simulation (don't move hardware)
skipProcessing = true;    % true = Don't generate reconstruction files yet
verboseMode    = true;    % true = verbose + map

% AUTO-GRID MODE: build coordCenters_mm from ROI (roiSize_mm and overlapXY):

% Validate ROI dimensions
assert(all(mod(roiSize_mm, octProbeFOV_mm) == 0), ...
    'ROI size (X and Y) must be multiples of the FOV (%.2f mm)', octProbeFOV_mm);

% Convert ROI size [X Y] to [xMin xMax yMin yMax]
halfSizeX = roiSize_mm(1)/2;
halfSizeY = roiSize_mm(2)/2;
coordCenters_mm = [-halfSizeX halfSizeX -halfSizeY halfSizeY];


% EXPLICIT-CENTERS MODE (alternative to Auto-grid)
% Uncomment this block below if you want to set the points manually

coordCenters_mm = [ ...
     0, 1;     % up
    -1, 0;     % left
     1, 0;     % right
     0, -1];   % down  (-Y)


%% Perform the Scans
folders = yOCTScanMultipleCoordinates(coordCenters_mm, ...
            'pixelSize_um',             pixelSize_um, ...
            'octProbePath',             octProbePath, ...
            'octProbeFOV_mm',           octProbeFOV_mm, ...
            'xOverall_mm',              xOverall_mm, ...
            'yOverall_mm',              yOverall_mm, ...
            'overlapXY',                overlapXY, ...
            'zToScan_mm',               zToScan_mm, ...
            'focusSigma',               focusSigma, ...
            'tissueRefractiveIndex',    tissueRefractiveIdx, ...
            'oct2stageXYAngleDeg',      oct2stageXYAngleDeg, ...
            'dispersionQuadraticTerm',  dispersionQuadraticTerm, ...
            'focusPositionInImageZpix', focusPositionInImageZpix, ...
            'outputFolder',             outputFolder, ...
            'skipScanning',             skipScanning, ...
            'skipProcessing',           skipProcessing, ...
            'v',                        verboseMode);

fprintf('\\nScript ended. Created Folders:\\n');
disp(folders)


%% FUNCTION THAT DOES THE JOB
function folders = yOCTScanMultipleCoordinates(coordCenters_mm, varargin)
% yOCTScanMultipleTiles Scan multiple OCT volumes at user-defined centers.
%
%   folders = yOCTScanMultipleTiles(coordCenters_mm, 'Name', Value, ...)
%
%   REQUIRED
%     coordCenters_mm - Nx2 numeric array with [x y] centers (mm) to scan, **excluding** [0 0].
%
%   NAME-VALUE PAIRS (defaults shown in brackets)
%     'pixelSize_um'               (1)
%     'octProbePath'               ('probe.ini')
%     'octProbeFOV_mm'             (auto   1 mm for 10x, 0.5 mm for 40x)
%     'xOverall_mm'                ([-FOV/2 FOV/2])
%     'yOverall_mm'                ([-FOV/2 FOV/2])
%     'oct2stageXYAngleDeg'        (0)
%     'zToScan_mm'                 (auto)
%     'scanZJump_um'               (auto   15 µm for 10x, 5 µm for 40x)
%     'focusSigma'                 (auto   20 for 10x, 10 for 40x)
%     'tissueRefractiveIndex'      (1.33)
%     'skipScanning'               (false)
%     'skipProcessing'             (true)
%     'outputFolder'               (pwd)
%     'v'                          (true)
%     'dispersionQuadraticTerm'    ([])
%     'focusPositionInImageZpix'   ([])
%
%   OUTPUT
%     folders - cell array with full paths to each tile folder, in scan order.
%


%% 1. INPUT PARSING
p = inputParser;  % core
addParameter(p,'pixelSize_um',1,@isnumeric);
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'octProbeFOV_mm',[],@isnumeric);
addParameter(p,'xOverall_mm',[],@isnumeric);
addParameter(p,'yOverall_mm',[],@isnumeric);
addParameter(p,'oct2stageXYAngleDeg',0,@isnumeric);
addParameter(p,'zToScan_mm',[],@isnumeric);
addParameter(p,'scanZJump_um',[],@isnumeric);
addParameter(p,'focusSigma',[],@isnumeric);
addParameter(p,'tissueRefractiveIndex',1.33,@isnumeric);
% flags / misc
addParameter(p,'skipScanning',false,@islogical);
addParameter(p,'skipProcessing',true,@islogical);
addParameter(p,'outputFolder',pwd,@ischar);
addParameter(p,'v',true,@islogical);
addParameter(p,'dispersionQuadraticTerm',[],@isnumeric);
addParameter(p,'focusPositionInImageZpix',[],@isnumeric);
addParameter(p,'overlapXY',[0 0],@(x) isnumeric(x) && numel(x)==2 && all(x>=0) && all(x<1));

parse(p,varargin{:});
S = p.Results;

%% 2. LOAD PROBE & DEFAULTS
probe = yOCTReadProbeIniToStruct(S.octProbePath);
magTok = regexp(probe.ObjectiveName,'(\d+)x','tokens','once');
assert(~isempty(magTok),'Cannot parse objective magnification.');
mag = str2double(magTok{1});
if isempty(S.octProbeFOV_mm)
    S.octProbeFOV_mm = mag==10   * 1   + mag==40 * 0.5;
end
if isempty(S.xOverall_mm)
    S.xOverall_mm = [-S.octProbeFOV_mm/2  S.octProbeFOV_mm/2];
end
if isempty(S.yOverall_mm)
    S.yOverall_mm = [-S.octProbeFOV_mm/2  S.octProbeFOV_mm/2];
end
if isempty(S.scanZJump_um)
    S.scanZJump_um = mag==10 * 15 + mag==40 * 5;
end
if isempty(S.zToScan_mm)
    S.zToScan_mm = unique([-100 (-30:S.scanZJump_um:350) 0])*1e-3;
end
if isempty(S.focusSigma)
    S.focusSigma = mag==10 * 20 + mag==40 * 10;
end

%% 3. CLEAN & VALIDATE CENTERS
FOVx = diff(S.xOverall_mm);                    % tile width (mm)    
FOVy = diff(S.yOverall_mm);                    % tile height (mm)   
stepX = max(eps, FOVx*(1 - S.overlapXY(1)));   % center-to-center step in X
stepY = max(eps, FOVy*(1 - S.overlapXY(2)));   % center-to-center step in Y
tol   = 1e-6;

% Detect argument mode:
% - Nx2 -> explicit centers
% - 1x4 -> [xMin xMax yMin yMax] (auto-grid)
isAutoGrid = isnumeric(coordCenters_mm) && isequal(size(coordCenters_mm),[1 4]);

if isAutoGrid
    roiX = coordCenters_mm(1,1:2);
    roiY = coordCenters_mm(1,3:4);
    assert(roiX(1) < roiX(2) && roiY(1) < roiY(2), 'Invalid ROI [xMin xMax yMin yMax].');

    % Build center vectors so that each tile stays fully inside the ROI
    xStart = roiX(1) + FOVx/2;   xStop = roiX(2) - FOVx/2;
    yStart = roiY(1) + FOVy/2;   yStop = roiY(2) - FOVy/2;

    if xStart > xStop + tol
        xCenters = 0;
    else
        xCenters = xStart:stepX:xStop;
    end
    if yStart > yStop + tol
        yCenters = 0;
    else
        yCenters = yStart:stepY:yStop;
    end

    % Light rounding for stable folder names
    xCenters = round(xCenters, 3);
    yCenters = round(yCenters, 3);

    % Grid of centers
    [XX,YY] = meshgrid(xCenters, yCenters);
    coordCenters_mm = [XX(:), YY(:)];

else
    % Explicit centers mode (Nx2)
    assert(~isempty(coordCenters_mm) && isnumeric(coordCenters_mm) && size(coordCenters_mm,2)==2, ...
           'coordCenters_mm must be Nx2 (centers) or 1x4 ([xMin xMax yMin yMax]).');
    coordCenters_mm = round(coordCenters_mm, 3);
end

% Remove [0 0] if present and duplicates; origin will be inserted first
[~,ia]       = unique(coordCenters_mm,'rows','stable');   % unique indixes
dupIdx        = setdiff(1:size(coordCenters_mm,1), ia);   % repetead
userHadOrigin = any(all(abs(coordCenters_mm)<tol,2));     % ¿[0 0] given?

coordCenters_mm(all(abs(coordCenters_mm)<tol,2),:) = [];
coordCenters_mm = unique(coordCenters_mm,'rows','stable');

% Compose all centers with origin first
allCenters = [[0 0]; coordCenters_mm];

nTiles = size(allCenters,1);
folders = cell(nTiles,1);
for k=1:nTiles
    folders{k} = fullfile(S.outputFolder,sprintf('[%.2f, %.2f]',allCenters(k,1),allCenters(k,2)));
end

if S.v
    fprintf('\nTile order (%d):\n', nTiles);
    for k = 1:nTiles
        fprintf('  %2d  %s\n', k, folders{k});
    end
    if ~isempty(dupIdx)
        fprintf('Notice: %d duplicate center(s) were provided; only one scan will be performed for each duplicate.\n', numel(dupIdx));
    end
    if userHadOrigin
        fprintf('Notice: [0 0] was supplied explicitly; it will be scanned once as the first tile.\n');
    end
    if isAutoGrid
        fprintf('Auto-grid: ROI X=[%.3f, %.3f] (FOV=%.3f, step=%.3f | overlap=%.0f%%), ROI Y=[%.3f, %.3f] (FOV=%.3f, step=%.3f | overlap=%.0f%%)\n', ...
            roiX(1), roiX(2), FOVx, stepX, 100*S.overlapXY(1), ...
            roiY(1), roiY(2), FOVy, stepY, 100*S.overlapXY(2));
    end
end

%% 4. PREVIEW MAP (coverage heatmap + overlap)
if S.v
    % Determine visualization ROI
    FOVx = diff(S.xOverall_mm);
    FOVy = diff(S.yOverall_mm);

    usingAutoGrid = exist('isAutoGrid','var') && isAutoGrid;
    hasOverlap    = any(S.overlapXY > 0);

    if usingAutoGrid
        roiXv = roiX;
        roiYv = roiY;
    else
        % Bounding box around explicit centers
        roiXv = [min(allCenters(:,1)) + S.xOverall_mm(1), max(allCenters(:,1)) + S.xOverall_mm(2)];
        roiYv = [min(allCenters(:,2)) + S.yOverall_mm(1), max(allCenters(:,2)) + S.yOverall_mm(2)];
    end

    % Raster grid for coverage map
    pxPerMM = 150;
    nx = max(100, round((roiXv(2)-roiXv(1))*pxPerMM));
    ny = max(100, round((roiYv(2)-roiYv(1))*pxPerMM));
    xg = linspace(roiXv(1), roiXv(2), nx);
    yg = linspace(roiYv(1), roiYv(2), ny);
    [Xg,Yg] = meshgrid(xg, yg);
    coverCount = zeros(ny, nx, 'uint16');

    % Accumulate coverage count per pixel
    for k = 1:nTiles
        c = allCenters(k,:);
        inX = (Xg >= c(1) + S.xOverall_mm(1)) & (Xg <= c(1) + S.xOverall_mm(2));
        inY = (Yg >= c(2) + S.yOverall_mm(1)) & (Yg <= c(2) + S.yOverall_mm(2));
        coverCount = coverCount + uint16(inX & inY);
    end

    % Area metrics (only meaningful for auto-grid)
    dx = (roiXv(2)-roiXv(1)) / (nx-1);
    dy = (roiYv(2)-roiYv(1)) / (ny-1);
    dA = dx * dy;
    areaROI = (roiXv(2)-roiXv(1))*(roiYv(2)-roiYv(1));

    % Visualization
    figure('Name','Planned scan (coverage)');
    cc = min(coverCount, uint16(3));
    imagesc(xg, yg, double(cc)); axis equal; axis tight; set(gca,'YDir','normal'); hold on;

    % Categorical colormap: 0->white, 1->light blue, 2->orange, 3->red
    cmap = [1 1 1;
            0.80 0.90 1.00;
            1.00 0.80 0.20;
            1.00 0.30 0.30];
    colormap(gca, cmap);   % scope to this axes (in order to avoid global change)
    caxis([0 3]);          % map values {0,1,2,3} to the rows of cmap

    % ROI border only for auto-grid
    if usingAutoGrid
        plot([roiXv(1) roiXv(2) roiXv(2) roiXv(1) roiXv(1)], ...
             [roiYv(1) roiYv(1) roiYv(2) roiYv(2) roiYv(1)], 'k-', 'LineWidth', 1.0);
    end

    % Tile rectangles (dotted outlines)
    for k = 1:nTiles
        c = allCenters(k,:);
        rectangle('Position', [c(1)+S.xOverall_mm(1), c(2)+S.yOverall_mm(1), FOVx, FOVy], ...
                  'EdgeColor', [0 0 0], 'LineStyle', ':');
    end

    % Centers + order labels
    plot(allCenters(:,1), allCenters(:,2), 'ro', 'MarkerFaceColor','r');
    for k = 1:nTiles
        text(allCenters(k,1), allCenters(k,2), num2str(k), 'Color','w', ...
             'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
             'FontWeight','bold', 'FontSize', 8);
    end

    % Legend
    h0 = patch(NaN,NaN,[1 1 1]); h1 = patch(NaN,NaN,[0.80 0.90 1.00]);
    h2 = patch(NaN,NaN,[1.00 0.80 0.20]); h3 = patch(NaN,NaN,[1.00 0.30 0.30]);
    legend([h0 h1 h2 h3], {'No coverage','1x coverage','Overlap ≥2x','Overlap ≥3x'}, ...
        'Location','southoutside','Orientation','horizontal');
    xlabel('X [mm]'); ylabel('Y [mm]');

    % Build title dynamically
    titleStr = sprintf('Planned scan tiles | tiles=%d, FOV=%.3f mm', nTiles, FOVx);
    if usingAutoGrid
        stepX = max(eps, FOVx*(1 - S.overlapXY(1)));
        stepY = max(eps, FOVy*(1 - S.overlapXY(2)));
        titleStr = sprintf('%s, step=(%.3f, %.3f) mm', titleStr, stepX, stepY);
        if hasOverlap
            titleStr = sprintf('%s, overlap=(%d%%, %d%%)', titleStr, ...
                round(100*S.overlapXY(1)), round(100*S.overlapXY(2)));
        end
        titleStr = sprintf('%s\nROI=%.3f mm^2', titleStr, areaROI);
    end
    title(titleStr);
    hold off;
end

%% 5. SINGLE ESTIMATE OF DISPERSION/FOCUS
if ~S.skipProcessing && (isempty(S.dispersionQuadraticTerm)||isempty(S.focusPositionInImageZpix))
    if S.v, fprintf('Estimating dispersion & focus once...\n'); end
    [dq,fpix] = yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm( ...
                       'octProbePath',S.octProbePath, ...
                       'tissueRefractiveIndex',S.tissueRefractiveIndex, ...
                       'skipHardware',S.skipScanning);
    if isempty(S.dispersionQuadraticTerm),  S.dispersionQuadraticTerm  = dq;  end
    if isempty(S.focusPositionInImageZpix), S.focusPositionInImageZpix = fpix; end
end

%% 6. INITIALISE HARDWARE (IF NEEDED)
if ~S.skipScanning
    [x0,y0,z0] = yOCTStageInit(S.oct2stageXYAngleDeg,NaN,NaN,S.v);
end

%% 7. LOOP OVER TILES
if ~S.skipScanning
    for k=1:nTiles
        ctr = allCenters(k,:);
        if S.v, fprintf('%s  >> TILE %d/%d  (%.2f, %.2f) mm\n',datestr(now,31),k,nTiles,ctr); end
    
        % Move stage
        if ~S.skipScanning
            yOCTStageMoveTo(x0+ctr(1),y0+ctr(2),NaN,S.v);
        end
    
        % Ensure folder
        if ~exist(folders{k},'dir'), mkdir(folders{k}); end
        volOut = fullfile(folders{k},'OCTVolume');
    
        % Scan
        if ~S.skipScanning
            yOCTScanTile(volOut, S.xOverall_mm, S.yOverall_mm, ...
                'octProbePath',          S.octProbePath, ...
                'tissueRefractiveIndex', S.tissueRefractiveIndex, ...
                'octProbeFOV_mm',        S.octProbeFOV_mm, ...
                'pixelSize_um',          S.pixelSize_um, ...
                'xOffset',               0, ...
                'yOffset',               0, ...
                'zDepths',               S.zToScan_mm, ...
                'oct2stageXYAngleDeg',   S.oct2stageXYAngleDeg, ...
                'skipHardware',          S.skipScanning, ...
                'v',                     S.v);
        end
    end
end
% Return stage home
if ~S.skipScanning
    yOCTStageMoveTo(x0,y0,NaN,S.v);
end

%% 8. PROCESS EACH TILE (IF REQUESTED)
if ~S.skipProcessing
    if S.v, fprintf('\nStarting processing of %d tiles...\n',nTiles); end
    for k=1:nTiles
        tiffName = fullfile(folders{k},sprintf('Image_[%.2f,%.2f].tiff',allCenters(k,1),allCenters(k,2)));
        volOut   = fullfile(folders{k},'OCTVolume');
        if S.v, fprintf('  Processing tile %d   %s\n',k,tiffName); end
        yOCTProcessTiledScan(volOut,{tiffName}, ...
            'focusPositionInImageZpix', S.focusPositionInImageZpix, ...
            'focusSigma',               S.focusSigma, ...
            'dispersionQuadraticTerm',  S.dispersionQuadraticTerm, ...
            'outputFilePixelSize_um',   S.pixelSize_um, ...
            'interpMethod',             'sinc5', ...
            'cropZAroundFocusArea',     true, ...
            'v',                        S.v);
    end
end

%% 9. CLEANUP
if S.v
    fprintf('\nDone!  skipScanning=%d, skipProcessing=%d\n',S.skipScanning,S.skipProcessing);
end
end
