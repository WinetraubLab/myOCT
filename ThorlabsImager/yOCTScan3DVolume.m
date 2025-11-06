function yOCTScan3DVolume(scanParamsStruct, outputDirectory)
% This function performs a single 3D OCT volume scan using the loaded OCT hardware (Ganymede or Gan632).
% It is called by yOCTScanTile for each tile position during multi-tile scanning.
%
% USAGE:
%   yOCTScan3DVolume(scanParamsStruct, outputDirectory)
%
% INPUTS:
%   scanParamsStruct - Structure containing scan parameters. Required fields in the struct:
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
% NOTE: 
%   Hardware selection (Ganymede vs Gan632) is automatic based on the system
%   loaded by yOCTLoadHardwareLib(). yOCTLoadHardwareLib() needs to be called before using this function.

%% Input validation
p = inputParser;
addRequired(p, 'scanParamsStruct', @isstruct);
addRequired(p, 'outputDirectory', @ischar);
parse(p, scanParamsStruct, outputDirectory);

% Validate required fields in scanParamsStruct
requiredFields = {'xOffset', 'yOffset', 'octProbe', 'tileRangeX_mm', 'tileRangeY_mm', ...
                  'nXPixelsInEachTile', 'nYPixelsInEachTile', 'nBScanAvg', 'v'};
missingFields = {};
for i = 1:length(requiredFields)
    if ~isfield(scanParamsStruct, requiredFields{i})
        missingFields{end+1} = requiredFields{i};
    end
end
if isfield(scanParamsStruct, 'octProbe')
    if ~isfield(scanParamsStruct.octProbe, 'DynamicOffsetX')
        missingFields{end+1} = 'octProbe.DynamicOffsetX';
    end
    if ~isfield(scanParamsStruct.octProbe, 'DynamicFactorX')
        missingFields{end+1} = 'octProbe.DynamicFactorX';
    end
end
if ~isempty(missingFields)
    error('Missing required fields in scanParamsStruct: %s', strjoin(missingFields, ', '));
end

%% Get the loaded hardware library
[octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLib();

%% Compute scan parameters
centerX_mm = scanParamsStruct.xOffset + scanParamsStruct.octProbe.DynamicOffsetX;       % X position offset [mm]
centerY_mm = scanParamsStruct.yOffset;                                    % Y position offset [mm]
rangeX_mm  = scanParamsStruct.tileRangeX_mm * scanParamsStruct.octProbe.DynamicFactorX; % Tile scan range in X [mm]
rangeY_mm  = scanParamsStruct.tileRangeY_mm;                              % Tile scan range in Y [mm]
rotationAngle_deg = 0;                                      % Rotation angle [deg]
sizeX_pix  = scanParamsStruct.nXPixelsInEachTile;                         % Number of X pixels (A-scans per B-scan)
sizeY_pix  = scanParamsStruct.nYPixelsInEachTile;                         % Number of Y pixels (B-scans in volume)
nBScanAvg  = scanParamsStruct.nBScanAvg;                                  % Number of B-scans to average
v = scanParamsStruct.v;                                                   % Verbose flag for logging

%% Dispatch to appropriate implementation based on system type
if ~skipHardware
    % Define retry parameters
    numRetries = 3;
    pauseDuration = 1; % Duration to pause (in seconds) between retries
    
    for attempt = 1:numRetries
        try
            % Remove folder if it exists
            if exist(outputDirectory,'dir')
                rmdir(outputDirectory, 's');
            end
            
            % Perform scan based on system type
            switch(octSystemName)
                case 'ganymede'
                    % Ganymede: Use C# DLL
                    ThorlabsImagerNET.ThorlabsImager.yOCTScan3DVolume(...
                        centerX_mm, ...
                        centerY_mm, ...
                        rangeX_mm, ...
                        rangeY_mm, ...
                        rotationAngle_deg, ...
                        sizeX_pix, sizeY_pix, ...
                        nBScanAvg, ...
                        outputDirectory); % Output folder (must not exist before scan)
                        
                case 'gan632'
                    % Gan632: Use Python module
                    octSystemModule.yOCTScan3DVolume(...
                        centerX_mm, ...
                        centerY_mm, ...
                        rangeX_mm, ...
                        rangeY_mm, ...
                        rotationAngle_deg, ...
                        int32(sizeX_pix), int32(sizeY_pix), ...
                        int32(nBScanAvg), ...
                        outputDirectory); % Output folder (must not exist before scan)
                        
                otherwise
                    error('Unknown OCT system: %s. Must call yOCTLoadHardwareLib() first.', octSystemName);
            end
            
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
else
    % Skip hardware scan 
    if v
        fprintf('%s 3D volume scan skipped (skipHardware = true)\n', datestr(datetime));
    end
end
end
