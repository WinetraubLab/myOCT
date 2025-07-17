function [roiAverageSurface_mm, isSurfaceInFocus] = yOCTComputeZOffsetSuchThatTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, varargin)
% This function checks the outputs from yOCTTissueSurfaceAutofocus,
% computes the average surface position and asserts that the tissue surface 
% is in focus. It will also explain to user how to adjust the z stage such 
% that tissue will be in focus.
%
% INPUTS:
%   surfacePosition_mm: provided by yOCTTissueSurfaceAutofocus
%   x_mm: provided by yOCTTissueSurfaceAutofocus
%   y_mm: provided by yOCTTissueSurfaceAutofocus
%   acceptableRange_mm: how far can tissue surface be from focus position
%       to be considered "good enough". Default: 0.025mm
%   roiToCheckSurfacePosition: Region Of Interest [x, y, width, height] mm to compute 
%       average surface and validate focus. Use [] to use the full scan area (default).
%   moveTissueToFocus: Move the Z stage automatically when the surface is out of focus.
%       (default = true; disabled if skipHardware = true)
%   validateFocusPosition: Set to false when photobleaching multiple tiles
%       and only need to compute the Z average surface offset value without 
%       validating if the tissue surface is in focus. Default = true.
%   v: Verbose mode for debugging purposes and visualization default is false.
% OUTPUTS:
% isSurfaceInFocus      = Resulting evaluation confirming whether the area is 
%                         in focus or not. (True = in focus; False = out of focus)
% roiAverageSurface_mm  = Average surface depth representing the Z offset of the checked ROI

%% Input checks

p = inputParser;
addParameter(p,'acceptableRange_mm',0.025,@isnumeric);
addParameter(p,'roiToCheckSurfacePosition',[],@(z) isempty(z) || ...
             (isnumeric(z) && numel(z)==4 && all(z(3:4)>0)));
addParameter(p,'moveTissueToFocus',true,@islogical);
addParameter(p,'validateFocusPosition',true,@islogical);
addParameter(p,'v',false,@islogical);
parse(p,varargin{:});
in = p.Results;

acceptableRange_mm          = in.acceptableRange_mm;
roiToCheckSurfacePosition   = in.roiToCheckSurfacePosition;
validateFocusPosition       = in.validateFocusPosition;
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
roiAverageSurface_mm = median(surfROI_mm,'omitnan');
isSurfaceInFocus = true; % Initial output before validation

%% Validate surface position
if validateFocusPosition
    % Assertion 1: Make sure we have enough surface position estimated
    surfNaNs = mean(isnan(surfROI_mm));
    if surfNaNs >= 0.2
        error('yOCT:SurfaceCannotBeEstimated', ...
              'Large part of the surface position cannot be estimated.');
    end
    surfROI_mm(isnan(surfROI_mm)) = [];

    % Assertion 2: Make sure that tissue is flat enough that it can all be in focus.
    p = 80;
    distFromSurface_mm = prctile(abs(surfROI_mm - roiAverageSurface_mm),p);
    if distFromSurface_mm > acceptableRange_mm
        error('yOCT:SurfaceCannotBeInFocus', ...
              "Tissue's shape is not flat, therefore it cannot all be in focus");
    end

    % Assertion 3: focus offset
    if abs(roiAverageSurface_mm) <= acceptableRange_mm % surface in focus
        isSurfaceInFocus = true; % We passed all tests
        if v
            fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', ...
                    datestr(datetime), roiAverageSurface_mm);
        end
    else  % surface out of focus
        isSurfaceInFocus = false;
    
        if roiAverageSurface_mm > 0
            direction = 'increase'; 
        else
            direction = 'decrease';
        end
    
        if ~in.moveTissueToFocus % Throw error if user doesn't want to autofocus
            error('yOCT:SurfaceOutOfFocus', ...
                  'Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.', ...
                  roiAverageSurface_mm, direction, abs(round(roiAverageSurface_mm,3)));
        end
        
        if v  % Give instructions if verbose mode
            fprintf('%s Surface out of focus by %.3f mm: please %s the stage Z position by %.3f mm to bring the tissue surface into focus.\n', ...
                    datestr(datetime), roiAverageSurface_mm, direction, abs(round(roiAverageSurface_mm,3)));
        end
    end
end
