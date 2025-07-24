function [zOffsetCorrection_mm, roiSurfaceMap_mm] = yOCTComputeZOffsetToFocusFromSurfaceROI( ...
    surfacePosition_mm, x_mm, y_mm, varargin)

% This function computes the Z offset to bring tissue into focus using the average surface
% position within a specified ROI from a surface map returned by yOCTFindTissueSurface.
% Returns both the average Z value and the used ROI surface map. 
% Useful for adjusting the Z-stage before scanning or photobleaching.
%
% INPUTS:
%   surfacePosition_mm: provided by yOCTTissueSurfaceAutofocus
%   x_mm: provided by yOCTTissueSurfaceAutofocus
%   y_mm: provided by yOCTTissueSurfaceAutofocus
%   roiToCheckSurfacePosition: Region Of Interest [x, y, width, height] mm to compute 
%       average surface. Use [] to use the full scan area (default).
%   v: Verbose mode for debugging purposes and visualization default is false.
%
% OUTPUTS:
%   zOffsetCorrection_mm : Average Z position of the tissue surface within the ROI.
%                          This value can be used as a Z-stage offset to bring the
%                          tissue into focus.
%   roiSurfaceMap_mm     : Cropped surface map (same dimensions as the selected ROI) 
%                          returned as a 2D matrix. Useful for analysis such as 
%                          surface validation. NaN values are preserved.

%% Input checks

p = inputParser;
addParameter(p,'roiToCheckSurfacePosition',[],@(z) isempty(z) || ...
             (isnumeric(z) && numel(z)==4 && all(z(3:4)>0)));
addParameter(p,'v',false,@islogical);
parse(p,varargin{:});
in = p.Results;

% acceptableRange_mm          = in.acceptableRange_mm;
roiToCheckSurfacePosition   = in.roiToCheckSurfacePosition;
v                           = in.v;

% Crop Region of Interest
if isempty(roiToCheckSurfacePosition)  % [] -> keep full area
    roiSurfaceMap_mm = surfacePosition_mm;

else % 4-element [x y w h]
    x0 = roiToCheckSurfacePosition(1);
    y0 = roiToCheckSurfacePosition(2);
    w  = roiToCheckSurfacePosition(3);
    h  = roiToCheckSurfacePosition(4);
    ix = (x_mm >= x0)     & (x_mm <= x0 + w);
    iy = (y_mm >= y0)     & (y_mm <= y0 + h);
    roiSurfaceMap_mm = surfacePosition_mm(iy,ix);
end

% Compute average surface position of the provided surfaceMap ROI
zOffsetCorrection_mm = median(roiSurfaceMap_mm(:), 'omitnan');
