function [surfacePosition_mm, x_mm, y_mm] = yOCTScanAndFindTissueSurface(varargin)
% This function uses the OCT to scan and then identify tissue surface from 
% the OCT image.
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
%       focus position to be considered "good enough". Default: 0.025mm, 
%       set to [] to skip assertion.
%   v: Verbose mode for debugging purposes and visualization default is 
%       false.
%   assertInFocusAcceptableRangeXYArea_mm : XY area (in mm) where the tissue 
%       surface must be in focus. This defines the region used to check 
%       whether the surface is within the assertInFocusAcceptableRange_mm 
%       to the focus plane. If it's out of range, the Z stage will be
%       automatically adjusted to bring the tissue into focus via
%       yOCTAssertTissueSurfaceIsInFocus. Accepted values:
%         • []             → uses the entire scan area (default)
%         • single number  → centered square. Example 0.5 → –0.25 to +0.25 mm
%         • 4 numbers      → [xMin xMax yMin yMax] custom rectangle (mm)
%   moveTissueToFocusIfNeeded: (Default = true) If skipHardware is false and
%       the surface is out of focus, having this true automatically moves the 
%       Z stage by the required amount. False will skip this movement.
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
addParameter(p,'xRange_mm',[-1 1]);
addParameter(p,'yRange_mm',[-1 1]);
addParameter(p,'pixelSize_um',25);
addParameter(p,'octProbeFOV_mm',[]);
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'temporaryFolder','./SurfaceAnalysisTemp/');
addParameter(p,'dispersionQuadraticTerm',79430000,@isnumeric);
addParameter(p,'focusPositionInImageZpix',NaN,@isnumeric);
addParameter(p,'assertInFocusAcceptableRange_mm',0.025);
addParameter(p,'assertInFocusAcceptableRangeXYArea_mm',[], ... 
    @(x) isempty(x) || isnumeric(x));
addParameter(p,'moveTissueToFocusIfNeeded',true,@islogical);
addParameter(p,'v',false);
addParameter(p,'skipHardware',false)

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

if isnan(in.focusPositionInImageZpix)
    error('Please provide a valid "focusPositionInImageZpix". Use yOCTFindFocusTilledScan to estimate.');
end
focusPositionInImageZpix = in.focusPositionInImageZpix;

roi = in.assertInFocusAcceptableRangeXYArea_mm; % early roi validation
if ~isempty(roi)
    if isscalar(roi)
        if roi <= 0
            error('assertInFocusAcceptableRangeXYArea_mm scalar value must be positive (width in mm).');
        end
    elseif ~(numel(roi)==4)
        error('assertInFocusAcceptableRangeXYArea_mm must be [] , a positive single number, or a 4‑element vector [xMin xMax yMin yMax].');
    end
end

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
    'focusPositionInImageZpix', focusPositionInImageZpix, ...
    'dispersionQuadraticTerm',  dispersionQuadraticTerm, ...
    'outputFilePixelSize_um',   pixelSize_um,...
    'cropZAroundFocusArea',     false, ...
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

%% Assert
if ~isempty(in.assertInFocusAcceptableRange_mm)
    % Decide which XY pixels to include (Region of Interest)
    if isempty(roi)          % [] -> keep full area
        surfROI_mm = surfacePosition_mm;
        xROI_mm    = x_mm;
        yROI_mm    = y_mm;

    elseif isscalar(roi)     % single value -> centered square of width
        half = roi/2;
        ix = (x_mm >= -half) & (x_mm <= half);
        iy = (y_mm >= -half) & (y_mm <= half);

        surfROI_mm = surfacePosition_mm(iy,ix);
        xROI_mm    = x_mm(ix);
        yROI_mm    = y_mm(iy);

    else                    % 4‑element vector [xMin xMax yMin yMax]
        ix = (x_mm >= roi(1)) & (x_mm <= roi(2));
        iy = (y_mm >= roi(3)) & (y_mm <= roi(4));

        surfROI_mm = surfacePosition_mm(iy,ix);
        xROI_mm    = x_mm(ix);
        yROI_mm    = y_mm(iy);
    end

    criticalFail  = false;
    outOfFocusErr = false;

    try
        yOCTAssertTissueSurfaceIsInFocus(surfROI_mm, xROI_mm, yROI_mm, ...
                                         in.assertInFocusAcceptableRange_mm);
    catch ME
        warning(ME.identifier, '%s', ME.message);
        switch ME.identifier
            case {'yOCT:SurfaceCannotBeEstimated', 'yOCT:SurfaceCannotBeInFocus'}
                criticalFail = true;           % never move Z stage in these cases
            case 'yOCT:SurfaceOutOfFocus'
                outOfFocusErr = true;          % we MAY move Z stage
            otherwise
                % unexpected error -> treat as critical
                criticalFail = true;
        end
    end

    roiVals = surfROI_mm(:);
    roiVals = roiVals(~isnan(roiVals));  % drop NaNs
    if isempty(roiVals)
        medianSurfacePosition_mm = NaN;
    else
        maxStageShift_mm = 0.20; % safety cap for maximum Z move (200 um)
        medianSurfacePosition_mm = median(roiVals);
        if abs(medianSurfacePosition_mm) > maxStageShift_mm
            medianSurfacePosition_mm = sign(medianSurfacePosition_mm) * maxStageShift_mm;
        end
    end

    % Move Z in stage if required (all conditions must be met to move it)
    needMove =  outOfFocusErr                                                       && ...  
                ~criticalFail                                                       && ...  
                ~isnan(medianSurfacePosition_mm)                                    && ...  
                abs(medianSurfacePosition_mm) > in.assertInFocusAcceptableRange_mm  && ...  
                ~in.skipHardware                                                    && ...
                in.moveTissueToFocusIfNeeded;

    if needMove
        [~,~,z0] = yOCTStageInit();  % query current Z
        try
            yOCTStageMoveTo(NaN, NaN, z0 + medianSurfacePosition_mm, v);
            warning('%s Stage auto‑moved by %.3f mm to refocus tissue surface.', ...
                    datestr(datetime), medianSurfacePosition_mm);

            % keep surface map consistent with new focus
            surfacePosition_mm = surfacePosition_mm - medianSurfacePosition_mm;

            if v
                fprintf('%s Stage Z successfully MOVED from %.3f mm to %.3f mm (OCT coord).\n', ...
                        datestr(datetime), z0, z0 + medianSurfacePosition_mm);
            end
        catch ME
            warning(ME.identifier, 'Stage move failed: %s', ME.message);
        end
    end
end
