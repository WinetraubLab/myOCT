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
%   roiToAssertFocus_mm: Region Of Interest [x, y, width, height] mm to assert focus.
%       Use [] to test the full scan area (default).
%   moveTissueToFocus: When set to true, it will move the Z stage automatically when the surface is out of focus.
%       When set to false, it will not move stage, but will notify user how to move stage back to focus.
%       Default is true. If skipHardware is set to true then moveTissueToFocus is forced to false.
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
addParameter(p,'roiToAssertFocus_mm',[], @(z) isempty(z) || ...
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
roi_mm                  = in.roiToAssertFocus_mm;
acceptableRange_mm      = in.assertInFocusAcceptableRange_mm;

if in.skipHardware % make sure we are moving the stage only if we don't skip hardware
    moveTissueToFocus = false;
else
    moveTissueToFocus = in.moveTissueToFocus;
end

% Return if skipHardware is true
if in.skipHardware % No need to continue, we can't scan because hardware is skipped

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
    surfacePosition_mm = zeros(nY, nX);
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
if ~isempty(acceptableRange_mm) % If acceptableRange_mm is empty, then no need to compute how stage should move
    
    % Assert focus and calculate Z offset correction to bring tissue into focus.
    % If the surface is out of focus and the user doesn't allow autofocus
    % (moveTissueToFocus is false), an error will be thrown with instructions 
    % for the user on how to manually adjust the Z stage
    [isSurfaceInFocus, zOffsetCorrection_mm] = yOCTAssertFocusAndComputeZOffset( ...
        surfacePosition_mm, x_mm, y_mm, ...
        'acceptableRange_mm',           acceptableRange_mm, ...
        'roiToCheckSurfacePosition',    roi_mm, ...
        'throwErrorIfOutOfFocus',       ~moveTissueToFocus,... Will throw an error if tissue is out of focus explaining the user how to move it back to focus
        'v',                            v);

    % Move the stage in Z if surface is out of focus, user wants to move and it's not a simulation
    needMove = ~isSurfaceInFocus && moveTissueToFocus && ~in.skipHardware;
    
    % Cap movement to safety limits only if need to move the stage
    maxMovementSafetyCap_mm = 0.10;  % 100 micron safety cap
    if needMove && ~isnan(zOffsetCorrection_mm) && ...
         abs(zOffsetCorrection_mm) > maxMovementSafetyCap_mm
        zOffsetCorrection_mm = sign(zOffsetCorrection_mm) * maxMovementSafetyCap_mm;
    end
    
    % Move the stage to bring tissue into focus if needed
    if needMove
        [~,~,z0] = yOCTStageInit();  % query current Z
        try
            % Move the stage
            yOCTStageMoveTo(NaN, NaN, z0 + zOffsetCorrection_mm, v);

            % Correct surface map by updating it with the new positions after movement
            surfacePosition_mm = surfacePosition_mm - zOffsetCorrection_mm;

            if v
                fprintf('%s Stage Z successfully MOVED from %.3f mm to %.3f mm to refocus tissue surface.\n', ...
                        datestr(datetime), z0, z0 + zOffsetCorrection_mm);
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
    fprintf('%s yOCTTissueSurfaceAutofocus function evaluation completed in %s.\n', ...
        datestr(datetime), datestr(totalDuration, 'HH:MM:SS'));
end