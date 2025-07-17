function [surfacePosition_mm, x_mm, y_mm] = yOCTTissueSurfaceAutofocus(varargin)
% This function uses the OCT to scan and identify the tissue surface from 
% the OCT image, evaluates focus, and (if requested) automatically moves 
% the Z-stage to bring the surface into focus.
%   xRange_mm, yRange_mm: what range to scan, default [-1 1] mm.
%   pixelSize_um: Pixel resolution for this analysis, default: 25 um.
%   octProbePath: Where is the probe.ini is saved to be used. Default 'probe.ini'.
%   octProbeFOV_mm: How much of the field of view to use from the probe during scans.
%   temporaryFolder: Directory for temporary files. 
%       These files will be deleted after analysis is completed.
%   dispersionQuadraticTerm: Dispersion compensation parameter.
%   focusPositionInImageZpix: For all B-Scans, this parameter defines the 
%       depth (Z, pixels) that the focus is located at.
%   assertInFocusAcceptableRange_mm: how far can tissue surface be from 
%       focus position to be considered "good enough". Default: 0.025mm.
%   roiToAssertFocus: Region Of Interest [x, y, width, height] mm to assert focus.
%       Use [] to test the full scan area (default).
%   moveTissueToFocus: Move the Z stage automatically when the surface is out of focus.
%       (default = true; disabled if skipHardware = true)
%   skipHardware: Set to true to skip hardware operation. Default: false.
%   v: Verbose mode for debugging purposes and visualization default is 
%       false.
% OUTPUTS:
%   - surfacePosition_mm - 2D matrix. dimensions are (y,x). What
%       height (mm) is image surface. Height measured from "user specified
%       tissue interface", higher value means deeper. See: 
%       https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/
%   - x_mm ,y_mm are the x,y positions that corresponds to surfacePosition(y,x).
%       Units are mm.

%% Parse inputs
p = inputParser;
addParameter(p,'xRange_mm',[-1 1]);
addParameter(p,'yRange_mm',[-1 1]);
addParameter(p,'pixelSize_um',25);
addParameter(p,'octProbeFOV_mm',[]);
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'temporaryFolder','./SurfaceAnalysisTemp/');
addParameter(p,'dispersionQuadraticTerm',79430000,@isnumeric);
addParameter(p,'focusPositionInImageZpix',NaN,@isnumeric);
addParameter(p,'assertInFocusAcceptableRange_mm',0.025);
addParameter(p,'roiToAssertFocus',[], @(z) isempty(z) || ...
         (isnumeric(z) && numel(z)==4 && all(z(3:4)>0)));
addParameter(p,'moveTissueToFocus',true,@islogical);
addParameter(p,'skipHardware',false);
addParameter(p,'v',false);

parse(p,varargin{:});
in = p.Results;

xRange_mm               = in.xRange_mm;
yRange_mm               = in.yRange_mm;
pixelSize_um            = in.pixelSize_um;
octProbeFOV_mm          = in.octProbeFOV_mm;
octProbePath            = in.octProbePath;
dispersionQuadraticTerm = in.dispersionQuadraticTerm;
temporaryFolder         = in.temporaryFolder;
v                       = in.v;
roi                     = in.roiToAssertFocus;
acceptableRange         = in.assertInFocusAcceptableRange_mm;


% Return if skipHardware is true
if in.skipHardware % No need to continue

    % How wide (X) and tall (Y) the requested scan area is:
    spanX_mm = xRange_mm(2) - xRange_mm(1); % total width  in millimetres
    spanY_mm = yRange_mm(2) - yRange_mm(1); % total height in millimetres

    % How many pixels would the real scan have:
    nX = ceil( spanX_mm * 1e3 / pixelSize_um ); % number of columns along X
    nY = ceil( spanY_mm * 1e3 / pixelSize_um ); % number of rows    along Y

    % Build coordinate vectors
    x_mm = ( xRange_mm(1) + (0:nX-1) .* (pixelSize_um/1e3) ).';
    y_mm = ( yRange_mm(1) + (0:nY-1) .* (pixelSize_um/1e3) ).';

    % Empty surface map
    surfacePosition_mm = NaN(nY, nX);
    return;
end

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
    'octProbeFOV_mm',  octProbeFOV_mm, ...
    'octProbePath',    octProbePath, ...
    'pixelSize_um',    pixelSize_um, ...
    'v',               v,  ...
    'skipHardware',    in.skipHardware ...
    );

%% Reconstruct OCT Image for Subsequent Surface Analysis
if (v)
    fprintf('%s Loading and processing the OCT scan...\n', datestr(datetime));
end
outputTiffFile = [temporaryFolder '\surface_analysis.tiff'];
yOCTProcessTiledScan(...
    volumeOutputFolder, ... Input
    {outputTiffFile},... Save only Tiff file as folder will be generated after smoothing
    'focusPositionInImageZpix', focusPositionInImageZpix, ...
    'dispersionQuadraticTerm',  dispersionQuadraticTerm, ...
    'outputFilePixelSize_um',   pixelSize_um,...
    'cropZAroundFocusArea',     false, ...
    'outputFilePixelSize_um',   [],...
    'v',                        v);
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
    'isVisualize', v, ...
    'octProbeFOV_mm', octProbeFOV_mm);

x_mm=dimensions.x.values;
y_mm=dimensions.y.values;
elapsedTimeSurfaceDetection_sec = toc(tSurface);
if (v)
    fprintf('%s Surface identification completed in %.2f seconds.\n', datestr(datetime), elapsedTimeSurfaceDetection_sec);
end

%% Bring tissue into focus
if ~isempty(acceptableRange)

    % Compute Z Offset
    [roiAverageSurface_mm, isSurfaceInFocus] = yOCTComputeZOffsetSuchThatTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, ...
    'acceptableRange_mm',           acceptableRange, ...
    'roiToCheckSurfacePosition',    roi, ...
    'moveTissueToFocus',            in.moveTissueToFocus,...
    'v',                            v);
    
    % Set limits
    maxMovementSafetyCap_mm = 0.10;  % 100 micron safety cap
    if ~isnan(roiAverageSurface_mm) && ...
         abs(roiAverageSurface_mm) > maxMovementSafetyCap_mm
        roiAverageSurface_mm = sign(roiAverageSurface_mm) * maxMovementSafetyCap_mm;
    end

    % Move Z in stage if required
    needMove = ~isSurfaceInFocus && in.moveTissueToFocus;
    if needMove
        [~,~,z0] = yOCTStageInit();  % query current Z
        try
            yOCTStageMoveTo(NaN, NaN, z0 + roiAverageSurface_mm, v);
            fprintf('%s Stage auto‑moved by %.3f mm to refocus tissue surface.\n', ...
                    datestr(datetime), roiAverageSurface_mm);

            % keep surface map consistent with new focus after movement
            surfacePosition_mm = surfacePosition_mm - roiAverageSurface_mm;

            if v
                fprintf('%s Stage Z successfully MOVED from %.3f mm to %.3f mm (OCT coord).\n', ...
                        datestr(datetime), z0, z0 + roiAverageSurface_mm);
            end
        catch ME
            error('yOCT:StageMoveFailed','Stage move failed: %s', ME.message);
        end
    end
end

%% Clean up temp data
if ~isempty(temporaryFolder) && exist(temporaryFolder, 'dir')
    rmdir(temporaryFolder, 's'); % Remove the output directory after processing
end
totalEndTime = datetime;  % Capture the ending time
totalDuration = totalEndTime - totalStartTime;
if (v)
    fprintf('%s yOCTScanAndFindTissueSurface function evaluation completed in %s.\n', ...
        datestr(datetime), datestr(totalDuration, 'HH:MM:SS'));
end