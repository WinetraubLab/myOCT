function [x0,y0,z0] = yOCTStageInit(oct2stageXYAngleDeg, ...
    minPosition, maxPosition,v)
% This function initializes translation stage and returns current position.
% INPUTS:
%   goct2stageXYAngleDeg - Optional, the rotation angle to convert between OCT
%       system and the stage, usually this angle is close to 0, but woth
%       calibration. See findMotorAngleCalibration.m for more information.
%       Rotation along X-Y plane
%   minPosition,maxPosition - if you would like to make sure that the stage
%       will be able to perform the movement, this input can help you!
%       set minPosition and maxPosition as the min and max translation you 
%       will experience and allow the stage to try it out.
%       minPosition, maxPosition are in milimiters and compared to current
%       stage position (x,y,z). Set to 0 or NaN if an axis shouldn't move
%   v - verbose mode, default is off
% OUTPUTS: 
%   x0,y0,z0 as defined in the coordinate systm defenition document.
%       Units are mm

%% Input Checks

if ~exist('minPosition','var') 
    minPosition = [0 0 0];
end
minPosition(isnan(minPosition)) = 0;
minPosition1 = zeros(1,3);
minPosition1(1:length(minPosition)) = minPosition;
minPosition = minPosition1;

if ~exist('maxPosition','var') 
    maxPosition = [0 0 0];
end
maxPosition(isnan(maxPosition)) = 0;
maxPosition1 = zeros(1,3);
maxPosition1(1:length(maxPosition)) = maxPosition;
maxPosition = maxPosition1;

if ~exist('v','var')
    v = false;
end

%% Initialization

if (v)
    fprintf('%s Initialzing Stage Hardware...\n\t(if Matlab is taking more than 2 minutes to finish this step, restart hardware and try again)\n',datestr(datetime));
end
ThorlabsImagerNETLoadLib();
z0=ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('z'); %Init stage
x0=ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('x'); %Init stage
y0=ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('y'); %Init stage

global goct2stageXYAngleDeg
if exist('oct2stageXYAngleDeg','var') && ~isnan(oct2stageXYAngleDeg)
    goct2stageXYAngleDeg = oct2stageXYAngleDeg;
else
    goct2stageXYAngleDeg = 0;
end

global gStageCurrentStagePosition_OCTCoordinates; % Position in OCT coordinate system (mm)
gStageCurrentStagePosition_OCTCoordinates = [x0;y0;z0];

global gStageCurrentStagePosition_StageCoordinates; % Position in stage coordinate system (mm)
gStageCurrentStagePosition_StageCoordinates = [x0;y0;z0]; % The same as OCT


%% Motion Range Test
if ~any(minPosition ~= maxPosition)
    return; % No motion range test
end
if (v)
    fprintf('%s Motion Range Test...\n\t(if Matlab is taking more than 2 minutes to finish this step, stage might be at it''s limit and need to center)\n',datestr(datetime));
end

s = 'xyz';
for i=1:length(s)
    if (minPosition(i) ~= maxPosition(i))
        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
            gStageCurrentStagePosition_StageCoordinates(i)+minPosition(i)); %Movement [mm]
        pause(0.5);
        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
            gStageCurrentStagePosition_StageCoordinates(i)+maxPosition(i)); %Movement [mm]
        pause(0.5);
        
        % Return home
        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
            gStageCurrentStagePosition_StageCoordinates(i)); %Movement [mm]
    end
end