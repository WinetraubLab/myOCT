function yOCTVerifyMotionRange(minPosition, maxPosition, v)
% Verify the stage can reach the requested motion range without collisions.
% Moves each axis to its minimum, then maximum, then back to the origin.
% Also registers the range so that later yOCTStageMoveTo calls can validate
% they stay within it.
%
% INPUTS:
%   minPosition - [x y z] in mm. Minimum position relative to stage origin.
%                 NaN values are treated as 0 on that axis.
%   maxPosition - [x y z] in mm. Maximum position relative to stage origin.
%                 NaN values are treated as 0 on that axis.
%   v           - (optional, default false) verbose mode
%
% Requires stage to be initialized via yOCTHardware('init', ...).
%
% After this function runs, the motion range is stored in globals and
% yOCTStageMoveTo will error if asked to move outside [minPosition, maxPosition].

if ~exist('v','var') || isempty(v)
    v = false;
end

%% Verify hardware + stage init
[octSystemModule, octSystemName, skipHardware] = yOCTHardware('status');

global gStageCurrentStagePosition_OCTCoordinates;
global gStageCurrentStagePosition_StageCoordinates;
if isempty(gStageCurrentStagePosition_OCTCoordinates)
    error('myOCT:yOCTHardware:stageNotInitialized', ...
        'Stage not initialized. Call yOCTHardware(''init'', ..., ''oct2stageXYAngleDeg'', deg) first.');
end

%% Normalize inputs
minPos = minPosition;
maxPos = maxPosition;
minPos(isnan(minPos)) = 0;
tmp = zeros(1,3); tmp(1:length(minPos)) = minPos; minPos = tmp;
maxPos(isnan(maxPos)) = 0;
tmp = zeros(1,3); tmp(1:length(maxPos)) = maxPos; maxPos = tmp;

%% Perform motion range test
if any(minPos ~= maxPos)
    if v
        fprintf('%s Motion Range Test...\n\t(if Matlab is taking more than 2 minutes to finish this step, stage might be at its limit and need to center)\n', datestr(datetime));
    end
    if ~skipHardware
        axes = 'xyz';
        for i = 1:length(axes)
            if minPos(i) ~= maxPos(i)
                switch octSystemName
                    case 'ganymede'
                        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i) + minPos(i));
                        pause(0.5);
                        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i) + maxPos(i));
                        pause(0.5);
                        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i));

                    case 'gan632'
                        octSystemModule.stage.yOCTStageSetPosition_1axis(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i) + minPos(i));
                        pause(0.5);
                        octSystemModule.stage.yOCTStageSetPosition_1axis(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i) + maxPos(i));
                        pause(0.5);
                        octSystemModule.stage.yOCTStageSetPosition_1axis(axes(i), ...
                            gStageCurrentStagePosition_StageCoordinates(i));

                    otherwise
                        error('Unknown OCT system: %s', octSystemName);
                end
                pause(0.5);
            end
        end
    else
        if v
            fprintf('%s Motion Range Test skipped (skipHardware = true)\n', datestr(datetime));
        end
    end
end

%% Register the verified range (in OCT coordinates, relative to origin at init)
% yOCTStageMoveTo will reject moves outside [origin + minPos, origin + maxPos].
global gRegisteredMotionRangeMin_OCT;
global gRegisteredMotionRangeMax_OCT;
origin = gStageCurrentStagePosition_OCTCoordinates(:)';
gRegisteredMotionRangeMin_OCT = origin + minPos;
gRegisteredMotionRangeMax_OCT = origin + maxPos;

end
