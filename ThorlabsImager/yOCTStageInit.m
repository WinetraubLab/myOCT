function [x0,y0,z0] = yOCTStageInit(oct2stageXYAngleDeg, ...
    minPosition, maxPosition, v)
% This function initializes translation stage and returns current position.
% INPUTS:
%   oct2stageXYAngleDeg - Optional, the rotation angle to convert between OCT
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

% Load library (should already be loaded to memory)
[octSystemModule, octSystemName, ~] = yOCTLoadHardwareLib();

% Determine which system to use based on octSystemName
switch(octSystemName)
    case 'gan632'
        % GAN632: Python stage control
        % TODO: Stage functions not yet implemented in Python module
        % Placeholder values until yOCTStageInit_1axis is implemented
        if (v)
            # fprintf('%s [GAN632] Initializing Python-based stage control (3 axes)...\n', datestr(datetime));
            fprintf('%s [GAN632] Stage control not yet implemented - using dummy values\n', datestr(datetime));
        end
        x0 = 0;
        y0 = 0;
        z0 = 0;
        
        % Future implementation (once Python functions are ready):
        % z0 = octSystemModule.yOCTStageInit_1axis('z');
        % x0 = octSystemModule.yOCTStageInit_1axis('x');
        % y0 = octSystemModule.yOCTStageInit_1axis('y');
        
    case 'ganymede'
        % Ganymede: C# DLL stage control
        ThorlabsImagerNETLoadLib();
        z0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('z');
        x0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('x');
        y0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('y');
        
    otherwise
        error('Unknown OCT system: %s', octSystemName);
end

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

% Perform motion range test based on system type
switch(octSystemName)
    case 'gan632'
        % GAN632: Use Python module for motion test
        % TODO: Implement once yOCTStageSetPosition_1axis is available
        % Future implementation:
        % axes_list = 'xyz';
        % for i=1:3
        %     if (minPosition(i) ~= maxPosition(i))
                % Test minimum position
        %         octSystemModule.yOCTStageSetPosition_1axis(axes_list(i), ...
        %             gStageCurrentStagePosition_StageCoordinates(i) + minPosition(i));
        %         pause(0.5);
        %         % Test maximum position
        %         octSystemModule.yOCTStageSetPosition_1axis(axes_list(i), ...
        %             gStageCurrentStagePosition_StageCoordinates(i) + maxPosition(i));
        %         pause(0.5);
        %         % Return home
        %         octSystemModule.yOCTStageSetPosition_1axis(axes_list(i), ...
        %             gStageCurrentStagePosition_StageCoordinates(i));
        %         pause(0.5);
        %     end
        % end
        
    case 'ganymede'
        % Ganymede: Use C# DLL for motion test
        s = 'xyz';
        for i=1:length(s)
            if (minPosition(i) ~= maxPosition(i))
                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                    gStageCurrentStagePosition_StageCoordinates(i)+minPosition(i));
                pause(0.5);
                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                    gStageCurrentStagePosition_StageCoordinates(i)+maxPosition(i));
                pause(0.5);
                
                % Return home
                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                    gStageCurrentStagePosition_StageCoordinates(i));
            end
        end
        
    otherwise
        error('Unknown OCT system: %s', octSystemName);
end