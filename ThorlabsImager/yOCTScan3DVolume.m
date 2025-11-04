function yOCTScan3DVolume(in, outputDirectory)
% This function automatically selects between Ganymede (C# DLL) or Gan632 (Python SDK)
% based on the loaded hardware library and uses it to perform a 3D OCT volume scan.
%
% USAGE:
%   yOCTScan3DVolume(in, outputDirectory)
%
% INPUTS:
%   in              - Structure containing scan parameters. Required fields:
%                       in.xOffset              - X position offset [mm]
%                       in.yOffset              - Y position offset [mm]
%                       in.octProbe.DynamicOffsetX - Probe's dynamic X offset [mm]
%                       in.octProbe.DynamicFactorX - Probe's dynamic X scaling factor
%                       in.tileRangeX_mm        - Tile scan range in X [mm]
%                       in.tileRangeY_mm        - Tile scan range in Y [mm]
%                       in.nXPixelsInEachTile   - Number of X pixels (A-scans per B-scan)
%                       in.nYPixelsInEachTile   - Number of Y pixels (B-scans in volume)
%                       in.nBScanAvg            - Number of B-scans to average
%
%   outputDirectory - Output folder path
%
% EXAMPLE:
%   yOCTScan3DVolume(in, 'C:\OCTData\Sample01\Scan_001');
%
% NOTE: 
%   This function calls yOCTLoadHardwareLib() internally to get the loaded
%   hardware library. Make sure to call yOCTLoadHardwareLib('Ganymede', false)
%   or yOCTLoadHardwareLib('Gan632', false) at least once before using this function.

%% Validate required fields exist
missingFields = {};
if ~isfield(in, 'xOffset'), missingFields{end+1} = 'xOffset'; end
if ~isfield(in, 'yOffset'), missingFields{end+1} = 'yOffset'; end
if ~isfield(in, 'octProbe'), missingFields{end+1} = 'octProbe'; end
if ~isfield(in, 'tileRangeX_mm'), missingFields{end+1} = 'tileRangeX_mm'; end
if ~isfield(in, 'tileRangeY_mm'), missingFields{end+1} = 'tileRangeY_mm'; end
if ~isfield(in, 'nXPixelsInEachTile'), missingFields{end+1} = 'nXPixelsInEachTile'; end
if ~isfield(in, 'nYPixelsInEachTile'), missingFields{end+1} = 'nYPixelsInEachTile'; end
if ~isfield(in, 'nBScanAvg'), missingFields{end+1} = 'nBScanAvg'; end
if ~isfield(in.octProbe, 'DynamicOffsetX'), missingFields{end+1} = 'octProbe.DynamicOffsetX'; end
if ~isfield(in.octProbe, 'DynamicFactorX'), missingFields{end+1} = 'octProbe.DynamicFactorX'; end
if ~isempty(missingFields)
    error('Missing required fields: %s', strjoin(missingFields, ', '));
end

%% Get the loaded hardware library
[octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLib();

%% Compute scan parameters
centerX_mm = in.xOffset + in.octProbe.DynamicOffsetX;       % X position offset [mm]
centerY_mm = in.yOffset;                                    % Y position offset [mm]
rangeX_mm  = in.tileRangeX_mm * in.octProbe.DynamicFactorX; % Tile scan range in X [mm]
rangeY_mm  = in.tileRangeY_mm;                              % Tile scan range in Y [mm]
rotationAngle_deg = 0;                                      % Rotation angle [deg]
sizeX_pix  = in.nXPixelsInEachTile;                         % Number of X pixels (A-scans per B-scan)
sizeY_pix  = in.nYPixelsInEachTile;                         % Number of Y pixels (B-scans in volume)
nBScanAvg  = in.nBScanAvg;                                  % Number of B-scans to average

%% Dispatch to appropriate implementation based on system type
if ~skipHardware
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
else
    % Skip hardware scan
    fprintf('3D volume scan skipped (skipHardware = true)\n');
end
end
