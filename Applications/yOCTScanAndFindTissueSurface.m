function [surfacePosition_mm, x_mm, y_mm, isSurfaceFocused] = yOCTScanAndFindTissueSurface(varargin)
% This function uses the OCT to scan and then identify tissue surface from 
% the OCT image.
% INPUTS (all inputs are parameters):
%   xRange_mm, yRange_mm - what range to scan, default [-1 1] mm.
%   pixel_size_um - Pixel resolution for this analysis, default: 15 um.
%   isVisualize - set to true to generate image heatmap visualization
%       figure. Default is false
%   octProbePath - OCT probe path, defaults to OCTP900 40x path. Adjust
%       as necessary for OBJECTIVE_DEPENDENT sizes ('10x', '40x') and 
%       scanning system dependent ('OCTP900' or '').
%   output_folder - Directory for temporary files, default './Surface_Analysis_Temp'.
%   octProbeFOV_mm - Field of view for the OCT probe in mm, default: 0.5 mm.
%   dispersionQuadraticTerm - Dispersion compensation parameter.
%   focusPositionInImageZpix - Z position [pix] of focus in each scan.
% OUTPUTS:
%   - surfacePosition_mm - 2D matrix. dimensions are (y,x). What
%       height (mm) is image surface. Height measured from "user specified
%       tissue interface", higher value means deeper. See: 
%       https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/
%   - x_mm ,y_mm are the x,y positions that corresponds to surfacePosition(y,x).
%       Units are mm.
%   isSurfaceFocused - Boolean indicating whether the tissue surface is correctly
%       positioned at the OCT focus, true if in focus, false otherwise.

%% Parse inputs
p = inputParser;
addParameter(p,'isVisualize',false);
addParameter(p,'octProbeFOV_mm',0.5)
addParameter(p,'xRange_mm',[-1 1]);
addParameter(p,'yRange_mm',[-1 1]);
addParameter(p,'pixel_size_um',15);
addParameter(p,'octProbePath',yOCTGetProbeIniPath('40x','OCTP900'));
addParameter(p,'output_folder','./Surface_Analysis_Temp');
addParameter(p,'dispersionQuadraticTerm',-1.454e+08);
addParameter(p,'focusPositionInImageZpix',491);

parse(p,varargin{:});
in = p.Results;
xRange_mm = in.xRange_mm;
yRange_mm = in.yRange_mm;
pixel_size_um = in.pixel_size_um;
octProbeFOV_mm = in.octProbeFOV_mm;
isVisualize = in.isVisualize;
octProbePath = in.octProbePath;
output_folder = in.output_folder;
dispersionQuadraticTerm = in.dispersionQuadraticTerm;
focusPositionInImageZpix = in.focusPositionInImageZpix;

%% Scan
totalStartTime = datetime;  % Capture the starting time
volumeOutputFolder = [output_folder '/OCTVolume/'];
disp('Please adjust the OCT focus such that it is precisely at the intersection of the tissue and the coverslip.')
fprintf('%s Scanning Volume...\n', datestr(datetime));
scanParameters = yOCTScanTile (...
    volumeOutputFolder, ...
    xRange_mm, ...
    yRange_mm, ...
    'octProbePath', octProbePath, ...
    'octProbeFOV_mm', octProbeFOV_mm, ...
    'pixelSize_um', pixel_size_um, ...
    'v',true  ...
    );

%% Reconstruct OCT Image for Subsequent Surface Analysis
fprintf('Generating image...\n');
outputTiffFile = [output_folder '\surface_analysis.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix',focusPositionInImageZpix,...
    'dispersionQuadraticTerm',dispersionQuadraticTerm,... Use default
    'cropZAroundFocusArea', false,...
    'interpMethod','sinc5', ...
    'v',true);
[logMeanAbs, dimensions, ~] = yOCTFromTif(outputTiffFile);
disp([newline, '-- Data loaded successfully.']);

%% Estimate tissue surface
fprintf('%s Identifying tissue surface...\n', datestr(datetime));
startTimeSurfaceDetection = datetime; % Start timing the surface detection
dimensions = yOCTChangeDimensionsStructureUnits(dimensions,'millimeters'); % Make sure it's in mm
surfacePosition_mm = yOCTFindTissueSurface(logMeanAbs, dimensions, 'isVisualize', isVisualize);
x_mm=dimensions.x.values;
y_mm=dimensions.y.values;
fprintf('Surface identification completed in %s.\n', datestr(datetime - startTimeSurfaceDetection, 'HH:MM:SS'));

%% Clean up
if exist(output_folder, 'dir')
    rmdir(output_folder, 's'); % Remove the output directory after processing
end
totalEndTime = datetime;  % Capture the ending time
totalDuration = totalEndTime - totalStartTime;
fprintf('Total surface analysis process completed in %s.\n', datestr(totalDuration, 'HH:MM:SS'));

%% Check if the average surface distance is within the acceptable range
average_surface_distance = nanmean(nanmean(surfacePosition_mm)); % Calculate the average surface distance
acceptableRange_mm = 0.01; % 10 microns is acceptable range
if isnan(average_surface_distance)
    warning(['No tissue identification possible. Likely the tissue is out of focus below the detection range. ' ...
        'Please manually adjust the stage UP to bring the tissue into focus.']);
    isSurfaceFocused = false; % Unable to verify if tissue surface is at focus
elseif abs(average_surface_distance) > acceptableRange_mm
    incrementsToAdjust = round(abs(average_surface_distance) / acceptableRange_mm); % Number of increments to adjust
    if average_surface_distance > 0 % Determine direction of adjustment
        direction = 'UP';
    else
        direction = 'DOWN';
    end
    warning('off', 'backtrace'); % Temporarily turn off backtrace for clear messaging
    warning(sprintf(['The average distance of the surface (%.4f mm) is out of range.\n\n', ...
        'Move the stage %s by %.2f mm to bring the tissue surface into focus. \n'], ...
        average_surface_distance, direction, incrementsToAdjust * acceptableRange_mm));
    warning('on', 'backtrace'); % Turn backtrace back on
    isSurfaceFocused = false; % Tissue surface is not at focus
else
    disp(['The average distance of the surface (', num2str(average_surface_distance, '%.4f'), ' mm) is within the acceptable range.']);
    disp('Tissue surface is precisely positioned at the OCT focus.');
    isSurfaceFocused = true; % Tissue surface is at focus
end
