function [dimOneTile, dimOutput] = yOCTProcessTiledScan_createDimStructure(tiledScanInputFolder, focusPositionInImageZpix)
% This is an auxilary function of yOCTProcessTiledScan designed to retun a
% dim structure for both a single tile and the entier tiledScan.
% The z direction of both dimOneTile and dimOutput is offset such that z=0 around the focus. Meaning
%     dimOutput.z == 0 when the focus is at the estimated tissue surface
%     dimOneTile.z == 0 when at the focus position (approximatly)
% If focusPositionInImageZpix is not provided, we won't make the correction
%
% INPUTS:
%   tiledScanInputFolder: data input folder
%   focusPositionInImageZpix: focus position for each zDepths (or one
%       number if focusPositionInImageZpix is the same for all depths).
%
% OUTPUTS:
%   dimOneTile: dim structure for both a single tile.
%   dimOutput: one overall dimensions structure for the entire stack.

%% Search and Load JSON file from  the tiledScanInputFolder
json = awsReadJSON([tiledScanInputFolder 'ScanInfo.json']);

%% Pretend processing the first scan to get the dimension structure of one tile
firstDataFolder = [tiledScanInputFolder json.octFolders{1}];
if (not(awsExist(firstDataFolder,'dir')))
    error('%s does not exist.', firstDataFolder);
end

dimOneTile = yOCTLoadInterfFromFile(firstDataFolder,'OCTSystem',json.OCTSystem,'peakOnly',true);
tmp = zeros(size(dimOneTile.lambda.values(:)));
dimOneTile = yOCTInterfToScanCpx (tmp, dimOneTile, 'n', json.tissueRefractiveIndex, 'peakOnly',true);

% Update dimensions to mm
dimOneTile = yOCTChangeDimensionsStructureUnits(dimOneTile, 'mm');

%% Update X&Y positions as they might not be reliable from scan

% Dimensions of one tile
if ~isfield(json,'xRange_mm')
    % Backward compatibility
    warning('Note, that "%s" contains an old version scan, this will be depricated by Jan 1st, 2025',tiledScanInputFolder)
    dimOneTile.x.values = json.xOffset+json.xRange*linspace(-0.5,0.5,json.nXPixels+1);
    dimOneTile.y.values = json.yOffset+json.yRange*linspace(-0.5,0.5,json.nYPixels+1);
else
    dimOneTile.x.values = json.xOffset+json.tileRangeX_mm*linspace(-0.5,0.5,json.nXPixels+1); 
    dimOneTile.y.values = json.yOffset+json.tileRangeY_mm*linspace(-0.5,0.5,json.nYPixels+1);
end
dimOneTile.x.values(end) = [];
dimOneTile.y.values(end) = [];

%% Correct dimOneTile.z to adjust for focus position
if ~exist('focusPositionInImageZpix','var') || any(isnan(focusPositionInImageZpix))
    % No adjustment because no focus info is provided
elseif length(focusPositionInImageZpix) == 1
    % One single focus value; shift z-dimensions with this value
    dimOneTile.z.values = dimOneTile.z.values - dimOneTile.z.values(focusPositionInImageZpix);
else
    % One value for each depth
    [~, idx] = min(abs(json.zDepths)); 
    end
    % Adjust z-dimensions using the focus index at zDepth 0
    dimOneTile.z.values = dimOneTile.z.values - dimOneTile.z.values(focusPositionInImageZpix(idx)); 
end


%% Compute pixel size
dx = diff(dimOneTile.x.values(1:2));
if (length(dimOneTile.y.values) > 1)
    dy = diff(dimOneTile.y.values(1:2));
else
    dy = 0; % No y axis
end
dz = diff(dimOneTile.z.values(1:2));

%% Compute dimensions of the entire output

zDepths_mm = json.zDepths;
if ~isfield(json,'xCenters_mm')
    % Backward compatibility
    xCenters_mm = json.xCenters;
    yCenters_mm = json.yCenters;
else
    xCenters_mm = json.xCenters_mm;
    yCenters_mm = json.yCenters_mm;
end

% Create a lattice from the first scan to the last one including the border.
% dx/2, dy/2, dz/2 is there to make sure we include edge (rounding error).
xAll_mm = (min(xCenters_mm)+dimOneTile.x.values(1)):dx:(max(xCenters_mm)+dimOneTile.x.values(end)+dx/2);xAll_mm = xAll_mm(:);
yAll_mm = (min(yCenters_mm)+dimOneTile.y.values(1)):dy:(max(yCenters_mm)+dimOneTile.y.values(end)+dy/2);yAll_mm = yAll_mm(:);
zAll_mm = (min(zDepths_mm )+dimOneTile.z.values(1)):dz:(max(zDepths_mm) +dimOneTile.z.values(end)+dz/2);zAll_mm = zAll_mm(:);

% Correct zAll_mm by removing the position where the tissue is at focus
[~, zeroIndex] = min(abs(zAll_mm)); 
zAll_mm = dz * ((1:length(zAll_mm)) - zeroIndex); % Shift to set start origin exactly at 0
zAll_mm = zAll_mm(:);

% Correct for the case of only one scan
if (length(xCenters_mm) == 1) %#ok<ISCL>
    xAll_mm = dimOneTile.x.values;
end
if (length(yCenters_mm) == 1) %#ok<ISCL> 
    yAll_mm = dimOneTile.y.values;
end

%% Create dimensions data structure
dimOutput.lambda = dimOneTile.lambda;
dimOutput.z = dimOneTile.z; % Template, we will update it soon
dimOutput.z.values = zAll_mm(:)';
dimOutput.z.origin = 'z=0 is “user specified tissue interface”';
dimOutput.x = dimOneTile.x;
dimOutput.x.origin = 'x=0 is OCT scanner origin when xCenters=0 scan was taken';
dimOutput.x.values = xAll_mm(:)';
dimOutput.x.index = 1:length(dimOutput.x.values);
dimOutput.y = dimOneTile.y;
dimOutput.y.values = yAll_mm(:)';
dimOutput.y.index = 1:length(dimOutput.y.values);
dimOutput.y.origin = 'y=0 is OCT scanner origin when yCenters=0 scan was taken';
dimOutput.aux = dimOneTile.aux;
