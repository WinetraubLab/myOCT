function [json] = yOCTScanTile(varargin)
% This function preforms an OCT Scan of a volume, and them tile around to
% stitch together multiple scans. Tiling will be done by 3D translation
% stage.
% INPUTS:
%   octFolder - folder to save all output information
%   xRange_mm - Area to scan [start, finish]. If area is larger than
%       lens's FOV, then tiling will automatically be used.
%   yRange_mm - Area to scan [start, finish]. If area is larger than
%       lens's FOV, then tiling will automatically be used. 
%       Set to a single value to scan a B-scan instead of 3D
%
% NAME VALUE PARAMETERS:
%   Parameter               Default Value   Notes
%   octProbePath            'probe.ini'     Where is the probe.ini is saved to be used.
%   octProbeFOV_mm          []              Keep empty to use FOV frome probe, or set to override probe's value.
%   octSystem               'Ganymede'      OCT system name ('Ganymede' or 'Gan632'). Default: 'Ganymede'.
%   pixelSize_um            1               What is the pixel size (in xy plane).
%   isVerifyMotionRange     true            Try the full range of motion before scanning, to make sure we won't get 'stuck' through the scan.
%   tissueRefractiveIndex   1.4             Refractive index of tissue.
%   xOffset,yOffset         0               (0,0) means that the center of the tile scaned is at the center of the galvo range aka lens optical axis. 
%                                           By appling offset, the center of the tile will be positioned differently.Units: mm
%   nBScanAvg               1               How many B Scan Averaging to scan
%   zDepths                 0               Scan depths to scan. Positive value is deeper. Units: mm
%	unzipOCTFile			true			Scan will scan .OCT file, if you would like to automatically unzip it set this to true.
% Debug parameters:
%   v                       true            verbose mode      
%   skipHardware            false           Set to true to skip hardware operation.
% OUTPUT:
%   json - config file
%
% How Tiling works. The assumption is that the OCT is stationary, and the
% sample is mounted on 3D translation stage that moves around to tile

%% Input Parameters
p = inputParser;

% OCT System
addParameter(p,'octSystem','Ganymede',@ischar);

% Output folder
addRequired(p,'octFolder',@ischar);

% Scan geometry parameters
addRequired(p,'xRange_mm')
addRequired(p,'yRange_mm')
addParameter(p,'zDepths',0,@isnumeric);
addParameter(p,'pixelSize_um',1,@isnumeric)

% Probe and stage parameters
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'octProbeFOV_mm',[]);
addParameter(p,'isVerifyMotionRange',true,@islogical);
addParameter(p,'xOffset',0,@isnumeric);
addParameter(p,'yOffset',0,@isnumeric);

% Other parameters
addParameter(p,'tissueRefractiveIndex',1.4,@isnumeric);
addParameter(p,'nBScanAvg',1,@isnumeric);
addParameter(p,'unzipOCTFile',true);

% Debugging
addParameter(p,'v',true,@islogical);
addParameter(p,'skipHardware',false,@islogical);

parse(p,varargin{:});

in = p.Results;
octFolder = in.octFolder;
v = in.v;
in = rmfield(in,'octFolder');
in = rmfield(in,'v');
in.units = 'mm'; % All units are mm
in.version = 1.1; % Version of this file

if ~exist(in.octProbePath,'file')
	error(['Cannot find probe file: ' in.octProbePath]);
end

% Validate that octSystem is specified and valid
validSystems = {'GAN632', 'Ganymede'};
if ~any(strcmpi(in.octSystem, validSystems))
    error(['Invalid OCT System: %s' newline ...
           'Valid options are: ''GAN632'' or ''Ganymede'''], in.octSystem);
end

%% Parse our parameters from probe
in.octProbe = yOCTReadProbeIniToStruct(in.octProbePath);

if isempty(in.octProbeFOV_mm)
    in.octProbeFOV_mm = in.octProbe.RangeMaxX; % Capture default value from probe ini
end

% Fill oct2stageXYAngleDeg from INI
in.oct2stageXYAngleDeg = in.octProbe.Oct2StageXYAngleDeg;

% If set, will protect lens from going into deep to the sample hiting the lens. Units: mm.
% The way it works is it computes what is the span of zDepths, compares that to working distance + safety buffer
% If the number is too high, abort will be initiated.
if isfield(in.octProbe,'ObjectiveWorkingDistance')
    objectiveWorkingDistance = in.octProbe.ObjectiveWorkingDistance;
else
    objectiveWorkingDistance = Inf;
end

if (in.nBScanAvg > 1)
    error('B Scan Averaging is not supported yet, it shifts the position of the scan');
end

if length(in.xRange_mm) ~= 2
    error('xRange_mm should be [start, finish]')
end
if length(in.yRange_mm) > 2
    error('yRange_mm should be [start, finish] or [mean]')
end
if length(in.yRange_mm) == 1 %#ok<ISCL>
    % Scan one pixel
    in.yRange_mm = in.yRange_mm + 0.5 * in.pixelSize_um/1e3 * [-1 1];
end

%% Split the scan to tiles

[in.xCenters_mm, in.yCenters_mm, in.tileRangeX_mm, in.tileRangeY_mm] = ...
    yOCTScanTile_XYRangeToCenters(in.xRange_mm, in.yRange_mm, in.octProbeFOV_mm);

% Check scan is within probe's limits
if ( ...
    ((in.xOffset+in.octProbe.DynamicOffsetX + in.tileRangeX_mm*in.octProbe.DynamicFactorX) > in.octProbe.RangeMaxX ) || ...
    ((in.yOffset + in.tileRangeY_mm > in.octProbe.RangeMaxY )) ...
    )
    error('Tring to scan outside lens range');
end

% Create scan center list
% Scan order, z changes fastest, x after, y latest
[in.gridXcc, in.gridZcc,in.gridYcc] = meshgrid(in.xCenters_mm,in.zDepths,in.yCenters_mm); 
in.gridXcc = in.gridXcc(:);
in.gridYcc = in.gridYcc(:);
in.gridZcc = in.gridZcc(:);
in.scanOrder = 1:length(in.gridZcc);
in.octFolders = arrayfun(@(x)(sprintf('Data%02d',x)),in.scanOrder,'UniformOutput',false);

%% Figure out number of pixels in each direction in one tile
in.nXPixelsInEachTile = ceil(in.tileRangeX_mm/(in.pixelSize_um/1e3));
in.nYPixelsInEachTile = ceil(in.tileRangeY_mm/(in.pixelSize_um/1e3));

%% Initialize hardware
if in.skipHardware
    % We are done, from now on it's just hardware execution
    in.OCTSystem = 'Unknown'; % This parameter can only be figured out when using hardware
    json = in;
    return;
end

yOCTScannerInit(in.octProbePath,v); % Init OCT

%% Check working distance
% Make sure depths are ok for working distance's sake 
if (max(in.zDepths) - min(in.zDepths) > objectiveWorkingDistance ...
        - 0.5) % Buffer
    error('zDepths requested are from %.1mm to %.1mm, which is too close to lens working distance of %.1fmm. Aborting', ...
        min(in.zDepths), max(in.zDepths), objectiveWorkingDistance);
end

%% Initialize Stage
if (v)
    fprintf('%s Initializing Stage (3 axes)...\n', datestr(datetime));
end

% Initialize stage (function auto-detects system based on octSystemModule)
if in.isVerifyMotionRange
    rg_min = [min(in.xCenters_mm) min(in.yCenters_mm) min(in.zDepths)];
    rg_max = [max(in.xCenters_mm) max(in.yCenters_mm) max(in.zDepths)];
else
    rg_min = NaN;
    rg_max = NaN;
end
[x0,y0,z0] = yOCTStageInit(in.oct2stageXYAngleDeg, rg_min, rg_max, v, octSystemModule);

if (v)
    fprintf('%s Hardware Initialization Complete (OCT + Stage)\n', datestr(datetime));
end

%% Make sure folder is empty
if exist(octFolder,'dir')
    rmdir(octFolder,'s');
end
mkdir(octFolder);

%% Preform the scan
for scanI=1:length(in.scanOrder)
    if (v)
        fprintf('%s Scanning Volume %02d of %d\n',datestr(datetime),scanI,length(in.scanOrder));
    end
        
    % Move to position
    yOCTStageMoveTo(x0+in.gridXcc(scanI), y0+in.gridYcc(scanI), z0+in.gridZcc(scanI), false, octSystemModule);

    % Create folder path to scan
    s = sprintf('%s\\%s\\',octFolder,in.octFolders{scanI});
    s = awsModifyPathForCompetability(s);

    % Scan
    octScan(in, s, octSystemModule);
    
    % Unzip if needed (for Ganymede system)
    if strcmpi(in.octSystem, 'Ganymede') && in.unzipOCTFile
        yOCTUnzipOCTFolder(strcat(s,'VolumeGanymedeOCTFile.oct'), s,true);
    end
    % NOTE: GAN632 Python module already extracts and splits files automatically
    
    if(scanI==1)
        [OCTSystem] = yOCTLoadInterfFromFile_WhatOCTSystemIsIt(s);
        in.OCTSystem = OCTSystem;
    end
    
end

%% Finalize

if (v)
    fprintf('%s Homing...\n', datestr(datetime));
end

% Return stage to home position
pause(0.5);
yOCTStageMoveTo(x0, y0, z0, false, octSystemModule);
pause(0.5);

if (v)
    fprintf('%s Finalizing\n', datestr(datetime));
end

% Close hardware based on system type
if strcmpi(in.octSystem, 'GAN632')
    % GAN632: Close Python scanner (stage not committed yet)
    % TODO: Uncomment when stage control is ready
    % try
    %     octSystemModule.yOCTStageShutdown();  % Close all axes + cleanup
    % catch ME
    %     error('Stage shutdown failed: %s', ME.message);
    % end
    octSystemModule.yOCTScannerClose();
    
elseif strcmpi(in.octSystem, 'Ganymede')
    % Ganymede: Close C# DLL scanner
    ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose(); %Close scanner
end

% Save scan configuration parameters
awsWriteJSON(in, [octFolder '\ScanInfo.json']);
json = in;

end

%% Scan Using Thorlabs
function octScan(in, s, octSystemModule)

% Define the number of retries
numRetries = 3;
pauseDuration = 1; % Duration to pause (in seconds) between retries

for attempt = 1:numRetries
    try
        % Remove folder if it exists
        if exist(s,'dir')
            rmdir(s, 's');
        end

        % Scan based on system type
        if strcmpi(in.octSystem, 'GAN632')
            % GAN632: Use Python module
            octSystemModule.yOCTScan3DVolume(...
                in.xOffset + in.octProbe.DynamicOffsetX, ... centerX [mm]
                in.yOffset, ... centerY [mm]
                in.tileRangeX_mm * in.octProbe.DynamicFactorX, ... rangeX [mm]
                in.tileRangeY_mm,  ... rangeY [mm]
                0,       ... rotationAngle [deg]
                int32(in.nXPixelsInEachTile), int32(in.nYPixelsInEachTile), ... SizeX,sizeY [# of pixels per tile]
                int32(in.nBScanAvg),       ... B Scan Average
                s ... Output directory, make sure this folder doesn't exist when starting the scan
                );
        elseif strcmpi(in.octSystem, 'Ganymede')
            % Ganymede: Use C# DLL
            ThorlabsImagerNET.ThorlabsImager.yOCTScan3DVolume(...
                in.xOffset + in.octProbe.DynamicOffsetX, ... centerX [mm]
                in.yOffset, ... centerY [mm]
                in.tileRangeX_mm * in.octProbe.DynamicFactorX, ... rangeX [mm]
                in.tileRangeY_mm,  ... rangeY [mm]
                0,       ... rotationAngle [deg]
                in.nXPixelsInEachTile, in.nYPixelsInEachTile, ... SizeX,sizeY [# of pixels per tile]
                in.nBScanAvg,       ... B Scan Average
                s ... Output directory, make sure this folder doesn't exist when starting the scan
                );
        end
        
        % If the function call is successful, break out of the loop
        break;
    catch ME
        % Notify the user that an exception has occurred
        fprintf('Attempt %d failed: %s\n', attempt, ME.message);

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
