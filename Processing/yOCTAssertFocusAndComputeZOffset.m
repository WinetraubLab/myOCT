function [zOffsetCorrection_mm, isSurfaceInFocus] = yOCTAssertFocusAndComputeZOffset( ...
    surfacePosition_mm, x_mm, y_mm, varargin)
% This function takes the outputs from yOCTTissueSurfaceAutofocus to
% compute the Z offset between the tissue surface and the current focus
% position and assert that the tissue surface is in focus. It will also explain
% to the user how to adjust the Z stage such that tissue will be in focus.
% INPUTS:
%   surfacePosition_mm: provided by yOCTTissueSurfaceAutofocus
%   x_mm: provided by yOCTTissueSurfaceAutofocus
%   y_mm: provided by yOCTTissueSurfaceAutofocus
%   acceptableRange_mm: How far can tissue surface be from focus position
%       to be considered "good enough". Default: 0.025mm
%   roiToCheckSurfacePosition: Region Of Interest [x, y, width, height] mm to compute 
%       average surface and validate focus. Use [] to use the full scan area (default).
%   throwErrorIfOutOfFocus: When set to true (default), the function will throw an error 
%       if the surface is out of focus. When set to false, it will not throw an error,
%       but will return the Z offset and print instructions for correction.
%   v: Verbose mode for debugging purposes and visualization default is false.
% OUTPUTS:
%   zOffsetCorrection_mm: Average Z distance between the current focus and the estimated 
%       tissue surface in the specified ROI. It can be used to move the Z stage and 
%       bring the tissue into focus. A positive value means the stage needs to move up;
%       a negative value means it should move down.
%   isSurfaceInFocus: Is tissue surface close to the focus position (within acceptableRange_mm).

%% Input checks

p = inputParser;
addParameter(p,'acceptableRange_mm',0.025,@isnumeric);
addParameter(p,'roiToCheckSurfacePosition',[],@(z) isempty(z) || ...
             (isnumeric(z) && numel(z)==4 && all(z(3:4)>0)));
addParameter(p,'throwErrorIfOutOfFocus',true,@islogical);
addParameter(p,'v',false,@islogical);
parse(p,varargin{:});
in = p.Results;

acceptableRange_mm      = in.acceptableRange_mm;
roiToCheck              = in.roiToCheckSurfacePosition;
throwErrorIfOutOfFocus  = in.throwErrorIfOutOfFocus;
v                       = in.v;

assert(size(surfacePosition_mm,1) == length(y_mm),'surfacePosition_mm first dimension should match y_mm')
assert(size(surfacePosition_mm,2) == length(x_mm),'surfacePosition_mm second dimension should match x_mm')

% Compute Z offset correction to bring tissue into focus and extract ROI from the surface map
if isempty(roiToCheck)  % if empty [] we use the whole surface area to check focus
    roiSurfaceMap_mm = surfacePosition_mm;
else % Trim the surface position to only include the provided ROI
    x0 = roiToCheck(1);
    y0 = roiToCheck(2);
    w  = roiToCheck(3);
    h  = roiToCheck(4);
    ix = (x_mm >= x0)     & (x_mm <= x0 + w);
    iy = (y_mm >= y0)     & (y_mm <= y0 + h);
    roiSurfaceMap_mm = surfacePosition_mm(iy,ix);
end

% Compute average surface position of the provided surfaceMap ROI
zOffsetCorrection_mm = median(roiSurfaceMap_mm(:), 'omitnan');

% Flatten surface map for numeric checks
roiSurfaceVec_mm = roiSurfaceMap_mm(:);

% Assertion 1: Make sure we have enough surface position estimated
surfNaNs = mean(isnan(roiSurfaceVec_mm));
if surfNaNs >= 0.2
    error('yOCT:SurfaceCannotBeEstimated', ...
          'Large part of the surface position cannot be estimated.');
end
roiSurfaceVec_mm(isnan(roiSurfaceVec_mm)) = [];

% Assertion 2: Make sure that tissue is flat enough that it can all be in focus.
p = 80;
distFromSurface_mm = prctile(abs(roiSurfaceVec_mm - zOffsetCorrection_mm),p);
if distFromSurface_mm > acceptableRange_mm
    error('yOCT:SurfaceCannotBeInFocus', ...
        "Tissue's shape is not flat, therefore it cannot all be in focus");
end

% Assertion 3: focus offset
if abs(zOffsetCorrection_mm) <= acceptableRange_mm % surface in focus
    isSurfaceInFocus = true; % We passed all tests
    if v
        fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', ...
                datestr(datetime), zOffsetCorrection_mm);
    end
else  % surface out of focus
    isSurfaceInFocus = false;

    if zOffsetCorrection_mm > 0
        direction = 'increase'; 
    else
        direction = 'decrease';
    end

    if throwErrorIfOutOfFocus % Throw error with instructions if autofocus is not allowed
        error('yOCT:SurfaceOutOfFocus', ...
              'Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.', ...
              zOffsetCorrection_mm, direction, abs(round(zOffsetCorrection_mm,3)));
    end
    
    if v  % Provide instructions to user if verbose mode is enabled and no error was thrown
        fprintf('%s Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.\n', ...
                datestr(datetime), zOffsetCorrection_mm, direction, abs(round(zOffsetCorrection_mm,3)));
    end
end
