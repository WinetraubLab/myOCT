function yOCTStageMoveTo (newx,newy,newz,v,octSystemModule)
% Move stage to new position.
% INPUTS:
%   newx,newy,newz - new stage position (mm). Set to nan if you would like
%       not to move stage along some axis. These new position units are in
%       OCT coordinate system units. A conversion between OCT coordinate
%       system to the stage coordinate system is done via
%       goct2stageXYAngleDeg which is set in yOCTStageInit
%   v - verbose mode (default is false)
%   octSystemModule - Python module for OCT control: Empty (default) for Ganymede.
%                     If empty/not provided, uses C# DLL (Ganymede) system.          

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

if ~exist('octSystemModule','var')
    octSystemModule = [];
end

%% Handle stage movement based on OCT system type
if ~isempty(octSystemModule)
    % GAN632: Python stage control (currently disabled for first release)
    if (v)
        fprintf('[GAN632] Stage movement skipped (not active in this release).\n');
    end
    % TODO: Uncomment when stage control is ready
    % if ~isnan(newx)
    %     octSystemModule.yOCTStageSetPosition_1axis('x', newx);
    % end
    % if ~isnan(newy)
    %     octSystemModule.yOCTStageSetPosition_1axis('y', newy);
    % end
    % if ~isnan(newz)
    %     octSystemModule.yOCTStageSetPosition_1axis('z', newz);
    % end
    return; % Exit early for GAN632
end

%% Ganymede: Original stage movement logic with coordinate transformation

%% Compute current and new coordinates in both OCT and stage coordinate sysetms
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

% Update
gStageCurrentStagePosition_OCTCoordinates = gStageCurrentStagePosition_OCTCoordinates + d;
gStageCurrentStagePosition_StageCoordinates = gStageCurrentStagePosition_StageCoordinates + d_;


%% Update position and move

if (v)
    fprintf('New Stage Position. ');
    fprintf('At Stage Coordinate System: (%.3f, %.3f, %.3f) mm. ',gStageCurrentStagePosition_StageCoordinates);
    fprintf('At OCT Coordinate System: (%.3f, %.3f, %.3f) mm.\n',gStageCurrentStagePosition_OCTCoordinates);
end

s = 'xyz';
for i=1:3
    if abs(d_(i)) > 0 % Move if motion of more than epsilon is needed 
        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(s(i),gStageCurrentStagePosition_StageCoordinates(i)); %Movement [mm]
    end
end

