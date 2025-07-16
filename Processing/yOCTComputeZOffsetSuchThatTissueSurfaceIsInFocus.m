function [isSurfaceInFocus, surfacePositionOutput_mm] = yOCTComputeZOffsetSuchThatTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, varargin)
% This function checks the outputs from yOCTTissueSurfaceAutofocus and
% asserts that the tissue surface is in focus. It will also explain to user
% how to adjust the z stage such that tissue will be in focus.
%
% INPUTS:
%   surfacePosition_mm: provided by yOCTScanAndFindTissueSurface
%   x_mm: provided by yOCTScanAndFindTissueSurface
%   y_mm: provided by yOCTScanAndFindTissueSurface
%   acceptableRange_mm: how far can tissue surface be from focus position
%       to be considered "good enough". Default: 0.025mm
%   roiToCheckSurfacePosition: Region Of Interest [x, y, width, height] mm to test focus.
%       Use [] to test the full scan area (default).
%   throwErrorIfAssertionFails: Stop with a clear error when set to true
%       (default) if any assertion check fails.
%   v: Verbose mode for debugging purposes and visualization default is false.
% OUTPUTS:
%   isSurfaceInFocus            = Resulting evaluation boolean confirming
%   whether the area is in focus or not. True in focus, false if not
%   surfacePositionOutput_mm    = Representative Z offset of the checked ROI (Median surface depth of that ROI)

%% Input checks

p = inputParser;
addParameter(p,'acceptableRange_mm',0.025,@isnumeric);
addParameter(p,'roiToCheckSurfacePosition',[],@(z) isempty(z) || ...
             (isnumeric(z) && numel(z)==4 && all(z(3:4)>0)));
addParameter(p,'throwErrorIfAssertionFails',true,@islogical);
addParameter(p,'v',false,@islogical);
parse(p,varargin{:});
in = p.Results;

acceptableRange_mm          = in.acceptableRange_mm;
roiToCheckSurfacePosition   = in.roiToCheckSurfacePosition;
throwErrorIfAssertionFails  = in.throwErrorIfAssertionFails;
v                           = in.v;

assert(size(surfacePosition_mm,1) == length(y_mm),'surfacePosition_mm first dimension should match y_mm')
assert(size(surfacePosition_mm,2) == length(x_mm),'surfacePosition_mm second dimension should match x_mm')

%% Compute surface position statistics

% Crop Region of Interest
if isempty(roiToCheckSurfacePosition)  % [] -> keep full area
    surfROI_mm = surfacePosition_mm;

else % 4-element [x y w h]
    x0 = roiToCheckSurfacePosition(1);
    y0 = roiToCheckSurfacePosition(2);
    w  = roiToCheckSurfacePosition(3);
    h  = roiToCheckSurfacePosition(4);
    ix = (x_mm >= x0)     & (x_mm <= x0 + w);
    iy = (y_mm >= y0)     & (y_mm <= y0 + h);
    surfROI_mm = surfacePosition_mm(iy,ix);
end
surfROI_mm = surfROI_mm(:);

% Representative offset for tissue surface
surfacePositionOutput_mm = median(surfROI_mm,'omitnan');

% Assertion 1: Make sure we have enough surface position estimated
if throwErrorIfAssertionFails
    surfNaNs = mean(isnan(surfROI_mm));
    if surfNaNs >= 0.2
        error('yOCT:SurfaceCannotBeEstimated', ...
              'Large part of the surface position cannot be estimated.');
    end
end
surfROI_mm(isnan(surfROI_mm)) = [];

% Assertion 2: Make sure that tissue is flat enough that it can all be in focus.
if throwErrorIfAssertionFails
    p = 80;
    distFromSurface_mm = prctile(abs(surfROI_mm - surfacePositionOutput_mm),p);
    if distFromSurface_mm > acceptableRange_mm
        error('yOCT:SurfaceCannotBeInFocus', ...
              "Tissue's shape is not flat, therefore it cannot all be in focus");
    end
end

% Assertion 3: focus offset
if abs(surfacePositionOutput_mm) <= acceptableRange_mm % surface in focus
    isSurfaceInFocus = true; % We passed all tests
    if v
        fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', ...
                datestr(datetime), surfacePositionOutput_mm);
    end
else  % surface out of focus
    isSurfaceInFocus = false;
    
    if surfacePositionOutput_mm > 0
        direction = 'increase'; 
    else
        direction = 'decrease';
    end

    if throwErrorIfAssertionFails % Throw error if out of focus
        error('yOCT:SurfaceOutOfFocus', ...
              'Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.', ...
              surfacePositionOutput_mm, direction, abs(round(surfacePositionOutput_mm,3)));
    end
    
    if v && ~throwErrorIfAssertionFails
        fprintf('%s Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.\n', ...
                datestr(datetime), surfacePositionOutput_mm, direction, abs(round(surfacePositionOutput_mm,3)));
    end
end
