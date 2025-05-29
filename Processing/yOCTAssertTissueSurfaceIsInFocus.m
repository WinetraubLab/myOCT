function yOCTAssertTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, acceptableRange_mm)
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

%% Input checks

assert(size(surfacePosition_mm,1) == length(y_mm),'surfacePosition_mm first dimension should match y_mm')
assert(size(surfacePosition_mm,2) == length(x_mm),'surfacePosition_mm second dimension should match x_mm')
if ~exist('acceptableRange_mm','var')
    acceptableRange_mm = 0.025;
end

%% Compute surface position statistics
surfacePosition_mm = surfacePosition_mm(:);

% Make sure we have enough surface position estimated
assert(sum(isnan(surfacePosition_mm))/length(surfacePosition_mm) < 0.2, "yOCT:SurfaceCannotBeEstimated", "Lage part of the surface position cannot be estimated");
surfacePosition_mm(isnan(surfacePosition_mm)) = [];

% Represent the tissue 
medianSurfacePosition_mm = median(surfacePosition_mm);

% Make sure that tissue is flat enough that it can all be in focus.
p = 80;
distFromMedian_mm = prctile(...
    abs(surfacePosition_mm-medianSurfacePosition_mm), p);
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