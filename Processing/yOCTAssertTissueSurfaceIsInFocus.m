function medianSurfacePosition_mm = yOCTAssertTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, acceptableRange_mm, assertInFocusAcceptableRangeXYArea_mm)
% This function checks the outputs from yOCTScanAndFindTissueSurface and
% asserts that the tissue surface is in focus. It will also explain to user
% how to adjust the z stage such that tissue will be in focus.
%
% INPUTS:
%   surfacePosition_mm: provided by yOCTScanAndFindTissueSurface
%   x_mm: provided by yOCTScanAndFindTissueSurface
%   y_mm: provided by yOCTScanAndFindTissueSurface
%   acceptableRange_mm: how far can tissue surface be from focus position
%       to be considered "good enough". Default: 0.025mm
%   assertInFocusAcceptableRangeXYArea_mm : XY area (in mm) where the tissue 
%       surface must be in focus. This defines the region used to check 
%       whether the surface is within the assertInFocusAcceptableRange_mm 
%       to the focus plane. Accepted values:
%         [] (default)   =  uses the entire scan area
%         single number  =  centered square area. Example 0.5 makes it –0.25 to +0.25 mm

%% Input checks

assert(size(surfacePosition_mm,1) == length(y_mm),'surfacePosition_mm first dimension should match y_mm')
assert(size(surfacePosition_mm,2) == length(x_mm),'surfacePosition_mm second dimension should match x_mm')
if ~exist('acceptableRange_mm','var')
    acceptableRange_mm = 0.025;
end

if ~exist('assertInFocusAcceptableRangeXYArea_mm','var') || isempty(assertInFocusAcceptableRangeXYArea_mm)
    assertInFocusAcceptableRangeXYArea_mm = [];
end

%% Compute surface position statistics

% Crop Region of Interest
if isempty(assertInFocusAcceptableRangeXYArea_mm) % [] -> keep full area
    surfROI_mm = surfacePosition_mm;

else % single value provided: centered square of width
    half = assertInFocusAcceptableRangeXYArea_mm/2;
    ix   = (x_mm >= -half) & (x_mm <=  half);
    iy   = (y_mm >= -half) & (y_mm <=  half);
    surfROI_mm = surfacePosition_mm(iy,ix);
end

surfROI_mm = surfROI_mm(:);

% Make sure we have enough surface position estimated
assert(sum(isnan(surfROI_mm))/length(surfROI_mm) < 0.2, "yOCT:SurfaceCannotBeEstimated", "Large part of the surface position cannot be estimated");
surfROI_mm(isnan(surfROI_mm)) = [];

% Represent the tissue 
medianSurfacePosition_mm = median(surfROI_mm);

% Make sure that tissue is flat enough that it can all be in focus.
p = 80;
distFromMedian_mm = prctile(...
    abs(surfROI_mm-medianSurfacePosition_mm), p);
if distFromMedian_mm>acceptableRange_mm
    error('yOCT:SurfaceCannotBeInFocus', ...
        "Tissue's shape is not flat, therefore it cannot all be in focus");
end

%% Instruct user how to change the surface position 
if abs(medianSurfacePosition_mm) > acceptableRange_mm
    if medianSurfacePosition_mm > 0 % Determine direction of adjustment
        direction = 'increase';
    else
        direction = 'decrease';
    end
    
    errorID = 'yOCT:SurfaceOutOfFocus';
    msg = sprintf(['The average distance of the surface (%.3fmm) is out of range.\n\n', ...
        'Please %s the stage Z position by %.3fmm to bring the tissue surface into focus.'], ...
        medianSurfacePosition_mm, direction, abs(round(medianSurfacePosition_mm, 3)));
    error(errorID, msg); 
end

fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', datestr(datetime), medianSurfacePosition_mm);
