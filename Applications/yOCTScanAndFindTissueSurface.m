function [surfacePosition_mm, x_mm, y_mm] = yOCTScanAndFindTissueSurface(varargin)
% This function uses the OCT to scan and then identify tissue surface from 
% the OCT image.
%   xRange_mm, yRange_mm: what range to scan, default [-1 1] mm.
%   pixelSize_um: Pixel resolution for this analysis, default: 25 um.
%   isVisualize: set to true to generate image heatmap visualization
%       figure. Default is false
%   octProbePath: Where is the probe.ini is saved to be used. Default 'probe.ini'.
%   octProbeFOV_mm: How much of the field of view to use from the probe during scans.
%   temporaryFolder: Directory for temporary files. 
%       These files will be deleted after analysis is completed.
%   dispersionQuadraticTerm: Dispersion compensation parameter.
%   focusPositionInImageZpix: For all B-Scans, this parameter defines the 
%       depth (Z, pixels) that the focus is located at. 
%   assertInFocusAcceptableRange_mm: how far can tissue surface be from 
%       focus position to be considered "good enough". Default: 0.025mm, 
%       set to [] to skip assertion.
%   v: Verbose mode for debugging purposes, default is false.
%   skipHardware: Set to true to skip hardware operation. Default: false.
% OUTPUTS:
%   - surfacePosition_mm - 2D matrix. dimensions are (y,x). What
%       height (mm) is image surface. Height measured from "user specified
%       tissue interface", higher value means deeper. See: 
%       https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/
%   - x_mm ,y_mm are the x,y positions that corresponds to surfacePosition(y,x).
%       Units are mm.

%% Parse inputs
p = inputParser;
addParameter(p,'isVisualize',false);
addParameter(p,'xRange_mm',[-1 1]);
addParameter(p,'yRange_mm',[-1 1]);
addParameter(p,'pixelSize_um',25);
addParameter(p,'octProbeFOV_mm',[]);
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'temporaryFolder','./SurfaceAnalysisTemp/');
addParameter(p,'dispersionQuadraticTerm',79430000,@isnumeric);
addParameter(p,'focusPositionInImageZpix',NaN,@isnumeric);
addParameter(p,'assertInFocusAcceptableRange_mm',0.025)
addParameter(p,'v',false);
addParameter(p,'skipHardware',false)

parse(p,varargin{:});
in = p.Results;

xRange_mm = in.xRange_mm;
yRange_mm = in.yRange_mm;
pixelSize_um = in.pixelSize_um;
isVisualize = in.isVisualize;
octProbeFOV_mm = in.octProbeFOV_mm;
octProbePath = in.octProbePath;
dispersionQuadraticTerm = in.dispersionQuadraticTerm;
temporaryFolder = in.temporaryFolder;
v = in.v;

if isnan(in.focusPositionInImageZpix)
    error('Please provide a valid "focusPositionInImageZpix". Use yOCTFindFocusTilledScan to estimate.');
end
focusPositionInImageZpix = in.focusPositionInImageZpix;

%% Scan
totalStartTime = datetime;  % Capture the starting time
volumeOutputFolder = [temporaryFolder '/OCTVolume/'];
if (v)
    fprintf('%s Scanning Volume...\n', datestr(datetime));
end
yOCTScanTile (...
    volumeOutputFolder, ...
    xRange_mm, ...
    yRange_mm, ...
    'octProbeFOV_mm', octProbeFOV_mm, ...
    'octProbePath', octProbePath, ...
    'pixelSize_um', pixelSize_um, ...
    'v',v,  ...
    'skipHardware', in.skipHardware ...
    );

if in.skipHardware % No need to continue
    surfacePosition_mm = 0;
    x_mm = 0;
    y_mm = 0;
    return;
end

%% Reconstruct OCT Image for Subsequent Surface Analysis
if (v)
    fprintf('%s Loading and processing the OCT scan...\n', datestr(datetime));
end
outputTiffFile = [temporaryFolder '\surface_analysis.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix',focusPositionInImageZpix,...
    'dispersionQuadraticTerm',dispersionQuadraticTerm,...
    'cropZAroundFocusArea', false,...
    'v',v);
[logMeanAbs, dimensions, ~] = yOCTFromTif(outputTiffFile);
dimensions = yOCTChangeDimensionsStructureUnits(dimensions,'millimeters'); % Make sure dimensions in mm
if (v)
    fprintf('%s -- Data loaded and processed successfully.\n', datestr(datetime));
end

%% Estimate tissue surface
if (v)
    fprintf('%s Identifying tissue surface...\n', datestr(datetime));
end
tSurface = tic;
surfacePosition_mm = yOCTFindTissueSurface( ...
    logMeanAbs, ...
    dimensions, ...
    'isVisualize', isVisualize, ...
    'octProbeFOV_mm', octProbeFOV_mm);

x_mm=dimensions.x.values;
y_mm=dimensions.y.values;
elapsedTimeSurfaceDetection_sec = toc(tSurface);
if (v)
    fprintf('%s Surface identification completed in %.2f seconds.\n', datestr(datetime), elapsedTimeSurfaceDetection_sec);
end

%% Clean up
if ~isempty(temporaryFolder) && exist(temporaryFolder, 'dir')
    rmdir(temporaryFolder, 's'); % Remove the output directory after processing
end
totalEndTime = datetime;  % Capture the ending time
totalDuration = totalEndTime - totalStartTime;
if (v)
    fprintf('%s yOCTScanAndFindTissueSurface function evaluation completed in %s.\n', ...
        datestr(datetime), datestr(totalDuration, 'HH:MM:SS'));
end

%% Assert
if ~isempty(in.assertInFocusAcceptableRange_mm)
    yOCTAssertTissueSurfaceIsInFocus( ...
        surfacePosition_mm, x_mm, y_mm, ...
        in.assertInFocusAcceptableRange_mm, v);
end
