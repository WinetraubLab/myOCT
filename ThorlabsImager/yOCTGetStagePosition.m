function [x0, y0, z0] = yOCTGetStagePosition()
% Return current stage position in OCT coordinate system (mm).
% Stage must have been initialized via yOCTHardware('init', ..., 'oct2stageXYAngleDeg', deg).
%
% OUTPUTS:
%   x0, y0, z0 - current stage position in mm (OCT coordinate system)
%
% USAGE:
%   [x0, y0, z0] = yOCTGetStagePosition();

global gStageCurrentStagePosition_OCTCoordinates;

if isempty(gStageCurrentStagePosition_OCTCoordinates)
    error('myOCT:yOCTHardware:stageNotInitialized', ...
        'Stage not initialized. Call yOCTHardware(''init'', ..., ''oct2stageXYAngleDeg'', deg) first.');
end

x0 = gStageCurrentStagePosition_OCTCoordinates(1);
y0 = gStageCurrentStagePosition_OCTCoordinates(2);
z0 = gStageCurrentStagePosition_OCTCoordinates(3);
end
