function [json] = yOCTTakeImagesTile(varargin)
%This function takes pictures all around for tiling
%stage.
%INPUTS:
%   imageFolder - folder to save all output information
%
%NAME VALUE INPUTS:
%   Parameter               Default Value   Notes
%   octProbePath            'probe.ini'     Where is the probe.ini is saved to be used
%   isVerifyMotionRange     true            Try the full range of motion before scanning, to make sure we won't get 'stuck' through the scan
%   lightRingIntensity      50              Light ring intensity (0-100) for taking fully illuminated images
%Scan tiling parameters, these will cerate a meshgrid relative to position
%   of stage at the beginning of the scan.
%   x,y,z parameters in tiling, are in the same direction as x,y,z of the
%   sacn, you can look at it as an extention of the size of the lens. 
%   xCenters,yCenters       0               Center positions of each tiles to scan (x,y) Units: mm. 
%                                           Example: 'xCenters', [0 1], 'yCenters', [0 1], 
%                                           will scan 4 OCT volumes centered around [0 0 1 1; 0 1 0 1] + [xOffset; yOffset]
%   zDepth                  0               What scan depth to use. Units: mm
%Debug parameters:
%   v                       true            verbose mode      
%OUTPUT:
%   json - config file
%
%How Tiling works. The assumption is that the OCT is stationary, and the
%sample is mounted on 3D translation stage that moves around to tile

%% Input Parameters
p = inputParser;
addRequired(p,'imageFolder',@isstr);

%General parameters
addParameter(p,'octProbePath','probe.ini',@isstr);
addParameter(p,'isVerifyMotionRange',true,@islogical);
addParameter(p,'lightRingIntensity',50,@(x)(isnumeric(x) & x>=0 & x<=100))
%Tile Parameters
addParameter(p,'xCenters',0,@isnumeric);
addParameter(p,'yCenters',0,@isnumeric);
addParameter(p,'zDepth',0,@isnumeric);

%Debugging
addParameter(p,'v',true,@islogical);

parse(p,varargin{:});

in = p.Results;
imageFolder = in.imageFolder;
v = in.v;
in = rmfield(in,'imageFolder');
in = rmfield(in,'v');
in.units = 'mm'; %All units are mm
in.version = 1; %Version of this file

if ~exist(in.octProbePath,'file')
	error(['Cannot find probe file: ' in.octProbePath]);
end

% Get OCT system from persistent library
[octSystemModule, octSystemName, ~] = yOCTLoadHardwareLib();

% Capitalize first letter for JSON compatibility with yOCTProcessTiledScan
in.OCTSystem = [upper(octSystemName(1)), octSystemName(2:end)];

%Load probe ini
ini = yOCTReadProbeIniToStruct(in.octProbePath);

% Fill oct2stageXYAngleDeg from INI
in.oct2stageXYAngleDeg = ini.Oct2StageXYAngleDeg;

%% Scan center list

%Scan order, z changes fastest, x after, y latest
[in.gridXcc,in.gridYcc] = meshgrid(in.xCenters,in.yCenters); 
in.gridXcc = in.gridXcc(:);
in.gridYcc = in.gridYcc(:);
scanOrder = 1:length(in.gridXcc);
in.imagesFP = arrayfun(@(x)(sprintf('Data%02d.jpg',x)),scanOrder,'UniformOutput',false);

%% Initialize hardware
if (v)
    fprintf('%s Initialzing Hardware...\n\t(if Matlab is taking more than 2 minutes to finish this step, restart hardware and try again)\n',datestr(datetime));
end

yOCTScannerInit(in.octProbePath, v); % Init OCT
[x0,y0] = yOCTStageInit(in.oct2stageXYAngleDeg);

%Set lightring power
if (v)
    fprintf('%s Setting light ring...\n',datestr(datetime));
end
ThorlabsImagerNET.ThorlabsImager.yOCTSetCameraRingLightIntensity(round(in.lightRingIntensity));


% Init stage and verify range if needed
if in.isVerifyMotionRange
    rg_min = [min(in.gridXcc) min(in.gridYcc) NaN];
    rg_max = [max(in.gridXcc) max(in.gridYcc) NaN];
else
    rg_min = NaN;
    rg_max = NaN;
end
[x0,y0,z0] = yOCTStageInit(in.oct2stageXYAngleDeg,rg_min,rg_max,v);

%Move to initial position to make a scan
if (in.zDepth ~= 0)
    yOCTStageMoveTo(NaN,NaN,z0+in.zDepth);
    pause(0.5);
end

if (v)
    fprintf('%s Done\n',datestr(datetime));
end

%% Make sure folder is empty
if exist(imageFolder,'dir')
    rmdir(imageFolder,'s');
end
mkdir(imageFolder);

%% Preform the scan
for scanI=1:length(scanOrder)
    if (v)
        fprintf('%s Scanning Image %02d of %d\n',datestr(datetime),scanI,length(scanOrder));
    end
        
    %Move to position
    yOCTStageMoveTo(x0+in.gridXcc(scanI),y0+in.gridYcc(scanI));
    
    %Make a folder
    s = sprintf('%s\\%s',imageFolder,in.imagesFP{scanI});
    s = awsModifyPathForCompetability(s);
    
    ThorlabsImagerNET.ThorlabsImager.yOCTCaptureCameraImage(s);
end

%% Finalize

if (v)
    fprintf('%s Homing...\n',datestr(datetime));
end

%Home (if required)
pause(0.5);
yOCTStageMoveTo(x0,y0,z0);
pause(0.5);

%Set lightring power
if (v)
    fprintf('%s Setting light to off...\n',datestr(datetime));
end
ThorlabsImagerNET.ThorlabsImager.yOCTSetCameraRingLightIntensity(0);

if (v)
    fprintf('%s Finalizing\n',datestr(datetime));
end
ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose(); %Close scanner

%Save scan configuration parameters
awsWriteJSON(in, [imageFolder '\ImageInfo.json']);
json = in;