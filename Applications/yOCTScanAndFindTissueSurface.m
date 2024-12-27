function [surfacePosition_mm, x_mm, y_mm, isSurfaceInFocus] = yOCTScanAndFindTissueSurface(varargin)
% This function uses the OCT to scan and then identify tissue surface from 
% the OCT image.
%   xRange_mm, yRange_mm - what range to scan, default [-1 1] mm.
%   pixel_size_um - Pixel resolution for this analysis, default: 15 um.
%   isVisualize - set to true to generate image heatmap visualization
%       figure. Default is false
%   octProbePath - Where is the probe.ini is saved to be used. Default 'probe.ini'.
%   output_folder - Directory for temporary files, default './Surface_Analysis_Temp'. 
%       These files will be deleted after analysis is completed.
%   dispersionQuadraticTerm - Dispersion compensation parameter.
%   focusPositionInImageZpix - For all B-Scans, this parameter defines the 
%       depth (Z, pixels) that the focus is located at. 
%       If set to NaN (default), yOCTFindFocusTilledScan will be executed 
%       to request user to select focus position.
%   acceptableRange_mm - Defines the range (in millimeters) within which the 
%       average detected tissue surface position is considered to be in focus.
%       Used to determine the output isSurfaceInFocus. Default is 25 microns.
%   v - Verbose mode for debugging purposes, default is false.
% OUTPUTS:
%   - surfacePosition_mm - 2D matrix. dimensions are (y,x). What
%       height (mm) is image surface. Height measured from "user specified
%       tissue interface", higher value means deeper. See: 
%       https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/
%   - x_mm ,y_mm are the x,y positions that corresponds to surfacePosition(y,x).
%       Units are mm.
%   isSurfaceInFocus - Boolean indicating whether the tissue surface is correctly
%       positioned at the OCT focus, true if in focus, false otherwise.

%% Parse inputs
p = inputParser;
addParameter(p,'isVisualize',false);
addParameter(p,'xRange_mm',[-1 1]);
addParameter(p,'yRange_mm',[-1 1]);
addParameter(p,'pixel_size_um',15);
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'output_folder','./Surface_Analysis_Temp');
addParameter(p,'dispersionQuadraticTerm',79430000,@isnumeric);
addParameter(p,'focusPositionInImageZpix',NaN,@isnumeric);
addParameter(p,'v',false);
addParameter(p, 'acceptableRange_mm', 0.025, @isnumeric)

parse(p,varargin{:});
in = p.Results;
xRange_mm = in.xRange_mm;
yRange_mm = in.yRange_mm;
pixel_size_um = in.pixel_size_um;
isVisualize = in.isVisualize;
octProbePath = in.octProbePath;
output_folder = in.output_folder;
dispersionQuadraticTerm = in.dispersionQuadraticTerm;
acceptableRange_mm = in.acceptableRange_mm;
v = in.v;

%% Scan
totalStartTime = datetime;  % Capture the starting time
volumeOutputFolder = [output_folder '/OCTVolume/'];
if (v)
    fprintf('%s Please adjust the OCT focus such that it is precisely at the intersection of the tissue and the coverslip.\n', datestr(datetime));
    fprintf('%s Scanning Volume...\n', datestr(datetime));
end
scanParameters = yOCTScanTile (...
    volumeOutputFolder, ...
    xRange_mm, ...
    yRange_mm, ...
    'octProbePath', octProbePath, ...
    'pixelSize_um', pixel_size_um, ...
    'v',v  ...
    );

%% Check if focusPositionInImageZpix is provided, if not use yOCTFindFocusTilledScan
if isempty(in.focusPositionInImageZpix)
    if (v)
        fprintf('%s Find focus position volume\n', datestr(datetime));
    end
    focusPositionInImageZpix = yOCTFindFocusTilledScan(volumeOutputFolder,...
        'reconstructConfig', {'dispersionQuadraticTerm', dispersionQuadraticTerm}, 'verbose', v);
else
    focusPositionInImageZpix = in.focusPositionInImageZpix;
end

%% Reconstruct OCT Image for Subsequent Surface Analysis
if (v)
    fprintf('%s Loading and processing the OCT scan...\n', datestr(datetime));
end
outputTiffFile = [output_folder '\surface_analysis.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix',focusPositionInImageZpix,...
    'dispersionQuadraticTerm',dispersionQuadraticTerm,...
    'cropZAroundFocusArea', false,...
    'v',v);
[logMeanAbs, dimensions, ~] = yOCTFromTif(outputTiffFile);
if (v)
    fprintf('%s -- Data loaded and processed successfully.\n', datestr(datetime));
end

%% Estimate tissue surface
if (v)
    fprintf('%s Identifying tissue surface...\n', datestr(datetime));
end
tic;
dimensions = yOCTChangeDimensionsStructureUnits(dimensions,'millimeters'); % Make sure it's in mm
surfacePosition_mm = yOCTFindTissueSurface(logMeanAbs, dimensions, 'isVisualize', isVisualize);
x_mm=dimensions.x.values;
y_mm=dimensions.y.values;
elapsedTimeSurfaceDetection_sec = toc;
if (v)
    fprintf('%s Surface identification completed in %.2f seconds.\n', datestr(datetime), elapsedTimeSurfaceDetection_sec);
end

%% Clean up
if exist(output_folder, 'dir')
    rmdir(output_folder, 's'); % Remove the output directory after processing
end
totalEndTime = datetime;  % Capture the ending time
totalDuration = totalEndTime - totalStartTime;
if (v)
    fprintf('%s yOCTScanAndFindTissueSurface function evaluation completed in %s.\n', ...
        datestr(datetime), datestr(totalDuration, 'HH:MM:SS'));
end

%% Check if the average surface distance is within the acceptable range
average_surface_distance_mm = nanmean(surfacePosition_mm(:)); % Calculate the average surface distance
if isnan(average_surface_distance_mm)
    warning(['No tissue identification possible. Likely the tissue is out of focus below the detection range. ' ...
        'Please manually increase the stage Z position to bring the tissue into focus.']);
    isSurfaceInFocus = false; % Unable to verify if tissue surface is at focus
elseif abs(average_surface_distance_mm) > acceptableRange_mm
    if average_surface_distance_mm > 0 % Determine direction of adjustment
        direction = 'increase';
    else
        direction = 'decrease';
    end
    warning('off', 'backtrace'); % Temporarily turn off backtrace for clear message formatting
    warning(sprintf(['The average distance of the surface (%.3fmm) is out of range.\n\n', ...
    'Please %s the stage Z position by %.3fmm to bring the tissue surface into focus. \n'], ...
    average_surface_distance_mm, direction, abs(round(average_surface_distance_mm, 3))));
    warning('on', 'backtrace'); % Turn backtrace back on
    isSurfaceInFocus = false; % Tissue surface is not at focus
else
    if (v)
        fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', datestr(datetime), average_surface_distance_mm);
        fprintf('%s Tissue surface is precisely positioned at the OCT focus.\n', datestr(datetime));
    end
    isSurfaceInFocus = true; % Tissue surface is at focus
end
