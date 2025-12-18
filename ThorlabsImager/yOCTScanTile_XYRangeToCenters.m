function [xCenters_mm, yCenters_mm, tileRangeX_mm, tileRangeY_mm] = ...
    yOCTScanTile_XYRangeToCenters(xRange_mm, yRange_mm, octProbeFOV_mm)
% This is an auxilary function to the main yOCTScanTile.
% This function will split a large scanning area (xRange, yRange) into
% specific tiles centered at xCenters, yCenters.
%
% INPUTS:
%   xRange_mm - [start, finish] of the x range in mm
%   yRange_mm - [start, finish] of the y range in mm
%   octProbeFOV_mm - probe FOV in mm, this specifies the size of each tile
%
% OUTPUTS:
%   xCenters_mm, yCenters_mm - Center positions of each tiles to scan (x,y)
%       Example: xCenters_mm=[0 1], xCenters_mm=[0 1], 
%       will scan 4 OCT volumes centered around [0 0 1 1; 0 1 0 1]
%   tileRangeX_mm, tileRangeY_mm - What is the size to scan in each tile. 
%       this value is the same as FOV or smaller in case not the entire
%       range is needed.

%% Input checks
xRange_mm = sort(xRange_mm);
yRange_mm = sort(yRange_mm);

% Check that the size is a multiplier of the FOV
xSize_mm = diff(xRange_mm);
ySize_mm = diff(yRange_mm);

% Use tolerance for floating point comparison (avoid precision issues)
tolerance_mm = 1e-6;

if ((xSize_mm > octProbeFOV_mm) && ...
    (abs(round(xSize_mm/octProbeFOV_mm) - (xSize_mm/octProbeFOV_mm)) > tolerance_mm))
    error('User requested to scan x=[%.2f to %.2f], but the size of the scan is not a multiplier of the FOV: %.2f. This is not implemented', xRange_mm(1),xRange_mm(2),octProbeFOV_mm);
end
if ((ySize_mm > octProbeFOV_mm) && ...
    (abs(round(ySize_mm/octProbeFOV_mm) - (ySize_mm/octProbeFOV_mm)) > tolerance_mm))
    error('User requested to scan y=[%.2f to %.2f], but the size of the scan is not a multiplier of the FOV: %.2f. This is not implemented', yRange_mm(1),yRange_mm(2),octProbeFOV_mm);
end


%% Compute scanning parameters
% Check that scan range is a whole number compared to octProbeFOV_mm
xSize_mm = diff(xRange_mm);
ySize_mm = diff(yRange_mm);
if ((xSize_mm > octProbeFOV_mm) && ...
    (abs(round(xSize_mm/octProbeFOV_mm) - (xSize_mm/octProbeFOV_mm)) > tolerance_mm))
    error('The range expresed in xOverall_mm should be a multiplier of octProbeFOV_mm');
end
if ((ySize_mm > octProbeFOV_mm) && ...
    (abs(round(ySize_mm/octProbeFOV_mm) - (ySize_mm/octProbeFOV_mm)) > tolerance_mm))
    error('The range expresed in yOverall_mm should be a multiplier of octProbeFOV_mm');
end

%% Define centers of the scan
xCenters_mm = ...
    (xRange_mm(1) + octProbeFOV_mm/2) : ...
    octProbeFOV_mm : ...
    (xRange_mm(2) - octProbeFOV_mm/2);
if isempty(xCenters_mm)
    xCenters_mm = mean(xRange_mm);
end
yCenters_mm = ...
    (yRange_mm(1) + octProbeFOV_mm/2) : ...
    octProbeFOV_mm : ...
    (yRange_mm(2) - octProbeFOV_mm/2);
if isempty(yCenters_mm)
    yCenters_mm = mean(yRange_mm);
end

% Define the range in x and y. according to FOV
if xSize_mm > octProbeFOV_mm
    % The xOverall scanning area is more than one FOV, use all of it
    tileRangeX_mm = octProbeFOV_mm;
else
    tileRangeX_mm = xSize_mm;
end
if ySize_mm > octProbeFOV_mm
    % The xOverall scanning area is more than one FOV, use all of it
    tileRangeY_mm = octProbeFOV_mm;
else
    tileRangeY_mm = ySize_mm;
end
