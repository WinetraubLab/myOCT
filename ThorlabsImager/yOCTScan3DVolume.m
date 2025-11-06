function yOCTScan3DVolume(scanParamsStruct, outputDirectory)
% Performs a single 3D OCT volume scan using Ganymede hardware.
% Called by yOCTScanTile for each tile position during multi-tile scanning.
%
% USAGE:
%   yOCTScan3DVolume(scanParamsStruct, outputDirectory)
%
% INPUTS:
%   scanParamsStruct - Structure containing scan parameters. Required fields:
%                       scanParamsStruct.xOffset              - X position offset [mm]
%                       scanParamsStruct.yOffset              - Y position offset [mm]
%                       scanParamsStruct.octProbe.DynamicOffsetX - Probe's dynamic X offset [mm]
%                       scanParamsStruct.octProbe.DynamicFactorX - Probe's dynamic X scaling factor
%                       scanParamsStruct.tileRangeX_mm        - Tile scan range in X [mm]
%                       scanParamsStruct.tileRangeY_mm        - Tile scan range in Y [mm]
%                       scanParamsStruct.nXPixelsInEachTile   - Number of X pixels (A-scans per B-scan)
%                       scanParamsStruct.nYPixelsInEachTile   - Number of Y pixels (B-scans in volume)
%                       scanParamsStruct.nBScanAvg            - Number of B-scans to average
%                       scanParamsStruct.v                    - Verbose flag for logging (true/false)
%
%   outputDirectory - Output folder path where scan data will be saved
%
% EXAMPLE:
%   yOCTScan3DVolume(scanParamsStruct, 'C:\OCTData\Sample01\Scan_001');

%% Validate required fields exist
missingFields = {};
if ~isfield(scanParamsStruct, 'xOffset'), missingFields{end+1} = 'xOffset'; end
if ~isfield(scanParamsStruct, 'yOffset'), missingFields{end+1} = 'yOffset'; end
if ~isfield(scanParamsStruct, 'octProbe'), missingFields{end+1} = 'octProbe'; end
if ~isfield(scanParamsStruct, 'tileRangeX_mm'), missingFields{end+1} = 'tileRangeX_mm'; end
if ~isfield(scanParamsStruct, 'tileRangeY_mm'), missingFields{end+1} = 'tileRangeY_mm'; end
if ~isfield(scanParamsStruct, 'nXPixelsInEachTile'), missingFields{end+1} = 'nXPixelsInEachTile'; end
if ~isfield(scanParamsStruct, 'nYPixelsInEachTile'), missingFields{end+1} = 'nYPixelsInEachTile'; end
if ~isfield(scanParamsStruct, 'nBScanAvg'), missingFields{end+1} = 'nBScanAvg'; end
if ~isfield(scanParamsStruct, 'v'), missingFields{end+1} = 'v'; end
if ~isfield(scanParamsStruct.octProbe, 'DynamicOffsetX'), missingFields{end+1} = 'octProbe.DynamicOffsetX'; end
if ~isfield(scanParamsStruct.octProbe, 'DynamicFactorX'), missingFields{end+1} = 'octProbe.DynamicFactorX'; end
if ~isempty(missingFields)
    error('Missing required fields: %s', strjoin(missingFields, ', '));
end

%% Compute scan parameters
centerX_mm = scanParamsStruct.xOffset + scanParamsStruct.octProbe.DynamicOffsetX;       % X position offset [mm]
centerY_mm = scanParamsStruct.yOffset;                                                  % Y position offset [mm]
rangeX_mm  = scanParamsStruct.tileRangeX_mm * scanParamsStruct.octProbe.DynamicFactorX; % Tile scan range in X [mm]
rangeY_mm  = scanParamsStruct.tileRangeY_mm;                                            % Tile scan range in Y [mm]
rotationAngle_deg = 0;                                                                  % Rotation angle [deg]
sizeX_pix  = scanParamsStruct.nXPixelsInEachTile;                                       % Number of X pixels (A-scans per B-scan)
sizeY_pix  = scanParamsStruct.nYPixelsInEachTile;                                       % Number of Y pixels (B-scans in volume)
nBScanAvg  = scanParamsStruct.nBScanAvg;                                                % Number of B-scans to average
v = scanParamsStruct.v;                                                                 % Verbose flag for logging

%% Perform 3D volume scan with retry logic
numRetries = 3;
pauseDuration = 1; % Duration to pause (in seconds) between retries

for attempt = 1:numRetries
    try
        % Remove folder if it exists
        if exist(outputDirectory,'dir')
            rmdir(outputDirectory, 's');
        end
        
        % Perform scan using Ganymede C# DLL
        ThorlabsImagerNET.ThorlabsImager.yOCTScan3DVolume(...
            centerX_mm, ...
            centerY_mm, ...
            rangeX_mm, ...
            rangeY_mm, ...
            rotationAngle_deg, ...
            sizeX_pix, sizeY_pix, ...
            nBScanAvg, ...
            outputDirectory); % Output folder (must not exist before scan)
            
        % If successful, break out of retry loop
        break;
        
    catch ME
        % Notify the user that an exception has occurred
        if v
            fprintf('%s Scan attempt %d failed: %s\n', datestr(datetime), attempt, ME.message);
        end
        
        % If this is the last attempt, rethrow the error
        if attempt == numRetries
            rethrow(ME);
        else
            % Pause before the next retry attempt
            pause(pauseDuration);
        end
    end
end
end
