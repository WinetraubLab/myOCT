function yOCTStageMoveTo (newx,newy,newz,v)
% Move stage to new position.
% INPUTS:
%   newx,newy,newz - new stage position (mm). Set to nan if you would like
%       not to move stage along some axis. These new position units are in
%       OCT coordinate system units. A conversion between OCT coordinate
%       system to the stage coordinate system is done via
%       goct2stageXYAngleDeg which is set in yOCTStageInit
%   v - verbose mode (default is false)

%% Input checks
if ~exist('newx','var')
    newx = NaN;
end

if ~exist('newy','var')
    newy = NaN;
end

if ~exist('newz','var')
    newz = NaN;
end

if ~exist('v','var')
    v = false;
end

% Load library (should already be loaded to memory)
[octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLibSetUp();

%% Compute current and new coordinates in both OCT and stage coordinate systems
global gStageCurrentStagePosition_StageCoordinates;
global gStageCurrentStagePosition_OCTCoordinates;

% Where do we need to move in coordinate system
d = [newx;newy;newz]-gStageCurrentStagePosition_OCTCoordinates(:);
d(isnan(d)) = 0; % Where there is nan, we don't need to move, keep as is

%% Compute where the new point is in Stage coordinate system
global goct2stageXYAngleDeg;
c = cos(goct2stageXYAngleDeg*pi/180);
s = sin(goct2stageXYAngleDeg*pi/180);
d_ = [c -s 0; s c 0; 0 0 1]*d;

% Update global position trackers
gStageCurrentStagePosition_OCTCoordinates = gStageCurrentStagePosition_OCTCoordinates + d;
gStageCurrentStagePosition_StageCoordinates = gStageCurrentStagePosition_StageCoordinates + d_;


%% Display new position

if (v)
    fprintf('New Stage Position. ');
    fprintf('At Stage Coordinate System: (%.3f, %.3f, %.3f) mm. ',gStageCurrentStagePosition_StageCoordinates);
    fprintf('At OCT Coordinate System: (%.3f, %.3f, %.3f) mm.\n',gStageCurrentStagePosition_OCTCoordinates);
end

%% Move stage - system-specific commands
if ~skipHardware
    s = 'xyz';
    for i=1:3
        if abs(d_(i)) > 0
            switch(octSystemName)
                case 'ganymede'
                    % Ganymede: C# DLL stage control
                    ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i), gStageCurrentStagePosition_StageCoordinates(i));
                    
                case 'gan632'
                    % Gan632: Python stage control
                    octSystemModule.stage.yOCTStageSetPosition_1axis(s(i), gStageCurrentStagePosition_StageCoordinates(i));
                    
                otherwise
                    error('Unknown OCT system: %s', octSystemName);
            end
        end
    end
else
    if (v)
        fprintf('Stage movement skipped (skipHardware = true)\n');
    end
end
