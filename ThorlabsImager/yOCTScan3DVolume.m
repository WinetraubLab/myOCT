function yOCTScan3DVolume(varargin)
% This function performs a single 3D OCT volume scan using the loaded OCT hardware (Ganymede or Gan632).
% It is called by yOCTScanTile for each tile position during multi-tile scanning.
%
% INPUTS:
%   centerX_mm       - X position center [mm]
%   centerY_mm       - Y position center [mm]
%   rangeX_mm        - Scan range in X [mm]
%   rangeY_mm        - Scan range in Y [mm]
%   sizeX_pix        - Number of pixels in the X direction, also known as scanning direction (A-scans per B-scan)
%   sizeY_pix        - Number of pixels in the Y direction (B-scans in volume)
%   nBScanAvg        - Number of B-scans to average
%   outputDirectory  - Output folder path where scan data will be saved
%   v                - Verbose flag for logging. Default: false
%
% NOTE: 
%   Hardware selection (Ganymede vs Gan632) is based on the system loaded by yOCTLoadHardwareLibSetUp().
%   yOCTLoadHardwareLibSetUp() needs to be called before using this function.

%% Input validation
p = inputParser;
addRequired(p, 'centerX_mm', @isnumeric);
addRequired(p, 'centerY_mm', @isnumeric);
addRequired(p, 'rangeX_mm', @isnumeric);
addRequired(p, 'rangeY_mm', @isnumeric);
addRequired(p, 'sizeX_pix', @isnumeric);
addRequired(p, 'sizeY_pix', @isnumeric);
addRequired(p, 'nBScanAvg', @isnumeric);
addRequired(p, 'outputDirectory', @ischar);
addParameter(p, 'v', false, @islogical);
parse(p, varargin{:});

in = p.Results;

%% Set rotation angle
rotationAngle_deg = 0; % Rotation angle [deg]

%% Get the loaded hardware library
[octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLibSetUp();

%% Dispatch to appropriate implementation based on system type
if ~skipHardware
    % Define retry parameters
    numRetries = 3;
    pauseDuration = 1; % Duration to pause (in seconds) between retries
    
    for attempt = 1:numRetries
        try
            % Remove folder if it exists
            if exist(in.outputDirectory,'dir')
                rmdir(in.outputDirectory, 's');
            end
            
            % Perform scan based on system type
            switch(octSystemName)
                case 'ganymede'
                    % Ganymede: Use C# DLL
                    ThorlabsImagerNET.ThorlabsImager.yOCTScan3DVolume(...
                        in.centerX_mm, ...
                        in.centerY_mm, ...
                        in.rangeX_mm, ...
                        in.rangeY_mm, ...
                        rotationAngle_deg, ...
                        in.sizeX_pix, in.sizeY_pix, ...
                        in.nBScanAvg, ...
                        in.outputDirectory); % Output folder (must not exist before scan)
                        
                case 'gan632'
                    % Gan632: Use Python module
                    octSystemModule.oct.yOCTScan3DVolume(...
                        in.centerX_mm, ...
                        in.centerY_mm, ...
                        in.rangeX_mm, ...
                        in.rangeY_mm, ...
                        rotationAngle_deg, ...
                        int32(in.sizeX_pix), int32(in.sizeY_pix), ...
                        int32(in.nBScanAvg), ...
                        in.outputDirectory); % Output folder (must not exist before scan)
                        
                otherwise
                    error('Unknown OCT system: %s. Must call yOCTLoadHardwareLibSetUp() first.', octSystemName);
            end
            
            % If successful, break out of retry loop
            break;
            
        catch ME
            % Notify the user that an exception has occurred
            if in.v
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
    if in.v
        fprintf('%s 3D volume scan skipped (skipHardware = true)\n', datestr(datetime));
    end
end
end