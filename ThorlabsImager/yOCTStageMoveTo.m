function yOCTStageMoveTo (newx,newy,newz,v)
% Move stage to new position.
% INPUTS:
%   newx,newy,newz - new stage position (mm). Set to nan if you would like
%       not to move stage along some axis. These new position units are in
%       OCT coordinate system units. The rotation angle between OCT and
%       stage coordinates is read from the Oct2StageXYAngleDeg field in
%       the probe INI by yOCTHardware('init').
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

% Verify stage is initialized (globals must be populated)
global gStageCurrentStagePosition_StageCoordinates;
global gStageCurrentStagePosition_OCTCoordinates;
if isempty(gStageCurrentStagePosition_OCTCoordinates)
    error('myOCT:yOCTHardware:stageNotInitialized', ...
        'Stage not initialized. Call yOCTHardware(''init'') first.');
end

[octSystemModule, octSystemName, skipHardware] = yOCTHardware('status');

% Verify target is within the registered motion range (if yOCTVerifyMotionRange was called). 
% NaN targets mean 'do not move that axis' and are excluded from the check.
global gRegisteredMotionRangeMin_OCT;
global gRegisteredMotionRangeMax_OCT;
if ~isempty(gRegisteredMotionRangeMin_OCT) && ~isempty(gRegisteredMotionRangeMax_OCT)
    target = [newx; newy; newz];
    checkAxes = ~isnan(target);
    rgMin = gRegisteredMotionRangeMin_OCT(:);
    rgMax = gRegisteredMotionRangeMax_OCT(:);
    outOfRange = checkAxes & (target < rgMin - eps | target > rgMax + eps);
    if any(outOfRange)
        error('myOCT:yOCTHardware:positionOutOfRange', ...
            ['Requested stage position (%.3f, %.3f, %.3f) mm (OCT coords) is outside ', ...
             'the registered motion range [%.3f %.3f %.3f] to [%.3f %.3f %.3f]. ', ...
             'Call yOCTVerifyMotionRange with a wider range before moving.'], ...
            newx, newy, newz, rgMin(1), rgMin(2), rgMin(3), rgMax(1), rgMax(2), rgMax(3));
    end
end

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
