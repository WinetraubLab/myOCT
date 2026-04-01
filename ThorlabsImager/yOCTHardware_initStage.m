function [x0,y0,z0] = yOCTHardware_initStage(oct2stageXYAngleDeg, ...
    minPosition, maxPosition,v)
% Helper function for yOCTHardware.
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

% Retry settings for transient stage init failures
stageInitMaxRetries = 3;
stageInitRetryDelaySec = 0.5;

% Load library (should already be loaded to memory)
[octSystemModule, octSystemName, skipHardware] = yOCTHardware('status');

% Initialize position values
if ~skipHardware
    % Determine which system to use based on octSystemName
    switch(octSystemName)
        case 'ganymede'
            % Ganymede: C# DLL stage control
            if (v)
                fprintf('%s [Ganymede] Initializing C# DLL-based stage control (3 axes)...\n', datestr(datetime));
            end
            z0 = stageInitWithRetry(@() ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('z'), ...
                'z', stageInitMaxRetries, stageInitRetryDelaySec, v);
            x0 = stageInitWithRetry(@() ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('x'), ...
                'x', stageInitMaxRetries, stageInitRetryDelaySec, v);
            y0 = stageInitWithRetry(@() ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('y'), ...
                'y', stageInitMaxRetries, stageInitRetryDelaySec, v);
            
        case 'gan632'
            % GAN632: Python stage control
            if (v)
                fprintf('%s [Gan632] Initializing Python-based stage control (3 axes)...\n', datestr(datetime));
            end
            z0 = stageInitWithRetry(@() octSystemModule.stage.yOCTStageInit_1axis('z'), ...
                'z', stageInitMaxRetries, stageInitRetryDelaySec, v);
            x0 = stageInitWithRetry(@() octSystemModule.stage.yOCTStageInit_1axis('x'), ...
                'x', stageInitMaxRetries, stageInitRetryDelaySec, v);
            y0 = stageInitWithRetry(@() octSystemModule.stage.yOCTStageInit_1axis('y'), ...
                'y', stageInitMaxRetries, stageInitRetryDelaySec, v);
            
        otherwise
            error('Unknown OCT system: %s', octSystemName);
    end
else
    % Skip hardware initialization - use simulation starting position
    if (v)
        fprintf('%s Stage initialization skipped (skipHardware = true), using origin (0,0,0)\n', datestr(datetime));
    end
    x0 = 0;
    y0 = 0;
    z0 = 0;
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
    fprintf('%s Motion Range Test...\n\t(if Matlab is taking more than 2 minutes to finish this step, stage might be at its limit and need to center)\n',datestr(datetime));
end

% Perform motion range test based on system type
if ~skipHardware
    s = 'xyz';
    for i=1:length(s)
        if (minPosition(i) ~= maxPosition(i))
            switch(octSystemName)
                case 'ganymede'
                    % Ganymede: Use C# DLL for motion test
                    ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                        gStageCurrentStagePosition_StageCoordinates(i)+minPosition(i));
                    pause(0.5);
                    ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                        gStageCurrentStagePosition_StageCoordinates(i)+maxPosition(i));
                    pause(0.5);
                    
                    % Return home
                    ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),...
                        gStageCurrentStagePosition_StageCoordinates(i));
                    
                case 'gan632'
                    % Gan632: Use Python module for motion test
                    octSystemModule.stage.yOCTStageSetPosition_1axis(s(i), ...
                        gStageCurrentStagePosition_StageCoordinates(i) + minPosition(i));
                    pause(0.5);
                    octSystemModule.stage.yOCTStageSetPosition_1axis(s(i), ...
                        gStageCurrentStagePosition_StageCoordinates(i) + maxPosition(i));
                    pause(0.5);
                    
                    % Return home
                    octSystemModule.stage.yOCTStageSetPosition_1axis(s(i), ...
                        gStageCurrentStagePosition_StageCoordinates(i));
                    
                otherwise
                    error('Unknown OCT system: %s', octSystemName);
            end
            pause(0.5);
        end
    end
else
    % Skip motion range test in simulation mode
    if (v)
        fprintf('%s Motion Range Test skipped (skipHardware = true)\n', datestr(datetime));
    end
end

end

function pos = stageInitWithRetry(initFcn, axisName, maxRetries, retryDelaySec, v)
for attempt = 1:maxRetries
    try
        pos = initFcn();
        return;
    catch ME
        errText = lower([ME.identifier ' ' ME.message]);
        isTransientXA = contains(errText, 'xa device exception 2') || ...
            (contains(errText, 'device exception 2') && contains(errText, 'xa'));

        if (~isTransientXA) || (attempt == maxRetries)
            rethrow(ME);
        end

        if v
            fprintf('%s Stage init axis %s failed (attempt %d/%d): %s\n', ...
                datestr(datetime), axisName, attempt, maxRetries, ME.message);
            fprintf('%s Retrying axis %s initialization in %.2f sec...\n', ...
                datestr(datetime), axisName, retryDelaySec);
        end
        pause(retryDelaySec);
    end
end
end
