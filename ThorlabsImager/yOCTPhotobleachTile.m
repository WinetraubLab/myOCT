function json = yOCTPhotobleachTile(varargin)
% This function photobleaches a pattern, the pattern can be bigger than the
% FOV of the scanner and then the script wii tile around to stitch together
% multiple scans.
% INPUTS:
%   ptStart: point(s) to strat line x and y (in mm). Dimensions are (dim,n)
%       dim is X,Y, n is number of lines. Line position is relative to 
%       current's stage position and relative to the opical axis of the lens 
%   ptEnd: corresponding end point (x,y), in mm
% NAME VALUE INPUTS:
%   Parameter               Default Value   Notes
% Probe defenitions:
%   octProbePath            'probe.ini'     Where is the probe.ini is saved to be used
% Photobleaching Parameters:
%   z                       0               Photobleaching depth (compared to corrent position in mm). 
%                                           Set to scallar to photobleach all lines in the same depth.
%                                           Or set to array equal to n to specify depth for each line.
%   surfaceMap              []              struct containing surfacePosition_mm, surfaceX_mm and surfaceY_mm which are outputs 
%                                           from yOCTScanAndFindTissueSurface representing the estimated tissue surface:
%                                               surfaceMap.surfacePosition_mm:  Z offsets at each (Y,X)
%                                               surfaceMap.surfaceX_mm:         X coordinates vector corresponding to surfacePosition_mm(Y,X)
%                                               surfaceMap.surfaceY_mm:         Y coordinates vector corresponding to surfacePosition_mm(Y,X)
%                                           If empty (default []) no surface‑based Z offset is applied
%                                           and the stage uses only the user‑supplied depth(s) in z.
%   exposure                15              How much time to expose each spot to laser light. Units sec/mm 
%                                           Meaning for each 1mm, we will expose for exposurePerLine sec 
%                                           If scanning at multiple depths, exposure will for each depth. Meaning two depths will be exposed twice as much. 
%   nPasses                 2               Should we expose to laser light in single or multiple passes over the same spot? 
%                                           The lower number of passes the better 
%   oct2stageXYAngleDeg     0               The angle to convert OCT coordniate system to motor coordinate system, see yOCTStageInit
%   maxLensFOV              []              What is the FOV allowed for photobleaching, by default will use lens defenition [mm].
% Constraints
%   enableZone              ones evrywhere  a function handle returning 1 if we can photobleach in that coordinate, 0 otherwise.
%                                           For example, this function will allow photobleaching only in a circle:
%                                           @(x,y)(x^2+y^2 < 2^2). enableZone accuracy see enableZoneAccyracy_mum.
%   bufferZoneWidth         10e-3           To prevent line overlap between near by tiles we use a buffer zone [mm].
%   enableZoneAccuracy      5e-3            Defines the evaluation step size of enable zone [mm].
%   minLineLength           10e-3           Minimal line length to photobleach, shorter lines are skipped [mm].
% Debug parameters:
%   v                       true            verbose mode  
%   skipHardware            false           Set to true if you would like to calculate only and not move or photobleach 
%   plotPattern             false           Plot the pattern of photonleach before executing on it.
%	laserToggleMethod		'OpticalSwitch' In order to turn off laser in between photobleach lines we can either use 'OpticalSwitch', or 'LaserPowerSwitch'
%											'OpticalSwitch' is faster and more reliable, but if you don't have optical switch in the system setup
%											The script can utilize 'LaserPowerSwitch' to turn on/off the diode. This is slower method with less accuracy but
%											can work if no optical switch in the setup.
%											View current setup: https://docs.google.com/document/d/1xHOKHVPpNBcxyRosTiVxx17hyXQ0NDnQGgiR3jcAuOM/edit
% OUTPUT:
%   json with the parameters used for photboleach

%% Input Parameters & Input Checks
p = inputParser;
addRequired(p,'ptStart');
addRequired(p,'ptEnd');

%General parameters
addParameter(p,'octProbePath','probe.ini',@isstr);
addParameter(p,'z',0,@isnumeric);
addParameter(p,'exposure',15,@isnumeric);
addParameter(p,'nPasses',2,@isnumeric);
addParameter(p,'enableZone',NaN);
addParameter(p,'oct2stageXYAngleDeg',0,@isnumeric);
addParameter(p,'maxLensFOV',[]);
addParameter(p,'bufferZoneWidth',10e-3,@isnumeric);
addParameter(p,'enableZoneAccuracy',5e-3,@isnumeric);
addParameter(p,'minLineLength',10e-3,@isnumeric);

addParameter(p,'v',true);
addParameter(p,'skipHardware',false);
addParameter(p,'plotPattern',false);
addParameter(p,'laserToggleMethod','OpticalSwitch');
addParameter(p,'surfaceMap', [], @(x) isempty(x) || (isstruct(x) && ...
    all(ismember({'surfacePosition_mm','surfaceX_mm','surfaceY_mm'}, fieldnames(x)))));

parse(p,varargin{:});
json = p.Results;
json.units = 'mm or mm/sec';

enableZone = json.enableZone;
json = rmfield(json,'enableZone');

%Check probe 
if ~exist(json.octProbePath,'file')
	error(['Cannot find probe file: ' json.octProbePath]);
end

%Load probe ini
ini = yOCTReadProbeIniToStruct(json.octProbePath);

%Load FOV
if isempty(json.maxLensFOV)
    json.FOV = [ini.RangeMaxX ini.RangeMaxY];
else
    if length(json.maxLensFOV)==2
        json.FOV = [json.maxLensFOV(1) json.maxLensFOV(2)];
    else
        json.FOV = [json.maxLensFOV(1) json.maxLensFOV(1)];
    end
end
json = rmfield(json,'maxLensFOV');

v = json.v;
json = rmfield(json,'v');

% Stage pause before moving
json.stagePauseBeforeMoving_sec = 0.5;

% Check number of passes and exposure
assert(isscalar(json.nPasses), 'Only 1 nPasses is permitted for all lines');
assert(isscalar(json.exposure), 'Only 1 exposure is permitted for all lines');

%% Pre processing, make a plan

% Split lines to photobleach instructions by FOV
photobleachPlan = yOCTPhotobleachTile_createPlan(...
    json.ptStart, json.ptEnd, json.z, json.FOV, json.minLineLength, ...
    json.bufferZoneWidth, json.enableZoneAccuracy, enableZone);

% Adjust Z stage to make sure photobleaching happens in the tissue based on surface map
halfFOVx = json.FOV(1)/2; % Half FOV in X 
halfFOVy = json.FOV(2)/2; % Half FOV in Y too in case FOV is ever a rectangle

for iXY = 1:numel(photobleachPlan)
    x_mm = photobleachPlan(iXY).stageCenterX_mm;
    y_mm = photobleachPlan(iXY).stageCenterY_mm;

    if isempty(json.surfaceMap)
        zSurf_mm = 0; % We assume flat surface if no surface map provided
    else
        S = json.surfaceMap;

        % Find indices in the surface map that fall within the current FOV
        xIndices = find(S.surfaceX_mm >= (x_mm - halfFOVx) & S.surfaceX_mm <= (x_mm + halfFOVx));
        yIndices = find(S.surfaceY_mm >= (y_mm - halfFOVy) & S.surfaceY_mm <= (y_mm + halfFOVy));

        if isempty(xIndices) || isempty(yIndices)
            % Tile is outside scanned surface area, we assume flat surface
            zSurf_mm = 0;
        else
            % Extract the submatrix corresponding to the specified range
            selectedValues    = S.surfacePosition_mm(yIndices, xIndices);

            % Calculate the median, ignoring NaN values
            zSurf_mm = median(selectedValues(:), 'omitnan');
            if isnan(zSurf_mm), zSurf_mm = 0; end
            
            % Limit offset to 100 microns to prevent lens damage
            if zSurf_mm > 0.1, zSurf_mm = 0.1; end
        end
    end

    % Store the surface offset and apply it to the Z-stage
    photobleachPlan(iXY).zOffsetDueToTissueSurface = zSurf_mm;
    photobleachPlan(iXY).stageCenterZ_mm = photobleachPlan(iXY).stageCenterZ_mm + zSurf_mm;
end

% Save the plan if user wants to return json
json.photobleachPlan = photobleachPlan;

% Plot the plan
if json.plotPattern
    % Estimate photobleach time
    lenCells        = {photobleachPlan.lineLength_mm};   % Each cell is a vector
    totalLineLength = sum([lenCells{:}]);                % Concatenate & sum
    estimatedPhotobleachTime_sec = totalLineLength*json.exposure; % sec
    
    yOCTPhotobleachTile_drawPlan(...
        photobleachPlan, json.FOV, estimatedPhotobleachTime_sec);
end

%% If skip hardware mode, we are done!
if (json.skipHardware)
    return;
end

%% Initialize Hardware Library

if (v)
    fprintf('%s Initialzing Hardware Dll Library... \n\t(if Matlab is taking more than 2 minutes to finish this step, restart matlab and try again)\n',datestr(datetime));
end
ThorlabsImagerNETLoadLib(); %Init library
if (v)
    fprintf('%s Done Hardware Dll Init.\n',datestr(datetime));
end

%% Initialize Translation Stage
[x0,y0,z0] = yOCTStageInit(json.oct2stageXYAngleDeg, NaN, NaN, v);

%Initialize scanner
ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(json.octProbePath); %Init OCT

if (v)
    fprintf('%s Initialzing Motorized Translation Stage Hardware Completed\n',datestr(datetime));
end

%% Before turning diode on, draw a line with galvo to see if it works
if (v)
    fprintf('%s Drawing Practice Line Without Laser Diode. This is The First Time Galvo Is Moving... \n\t(if Matlab is taking more than a few minutes to finish this step, restart hardware and try again)\n',datestr(datetime));
end
     
ThorlabsImagerNET.ThorlabsImager.yOCTPhotobleachLine( ...
    photobleachPlan(1).ptStartInFOV_mm(1,1), ... Start X
    photobleachPlan(1).ptStartInFOV_mm(2,1), ... Start Y
    photobleachPlan(1).ptEndInFOV_mm(1,1), ... End X
    photobleachPlan(1).ptEndInFOV_mm(2,1), ... End Y
    json.exposure * photobleachPlan(1).lineLength_mm(1), ... Exposure time sec
    json.nPasses); 
    
if (v)
    fprintf('%s Done. Drew Practice Line!\n',datestr(datetime));
end

%% Turn laser diode on

fprintf('%s Turning Laser Diode On... \n\t(if Matlab is taking more than 1 minute to finish this step, restart hardware and try again)\n',datestr(datetime));

if strcmpi(json.laserToggleMethod,'OpticalSwitch')
    % Initialize first
    yOCTTurnOpticalSwitch('init');
    
	% We set switch to OCT position to prevent light leak
	yOCTTurnOpticalSwitch('OCT'); % Set switch position away from photodiode
end
            
% Switch light on, write to screen only for first line
% ThorlabsImagerNET.ThorlabsImager.yOCTTurnLaser(true);  % Version using .NET
yOCTTurnLaser(true); % Version using Matlab directly

fprintf('%s Laser Diode is On\n',datestr(datetime)); 

%% Photobleach pattern

% Go over plan
for i=1:length(photobleachPlan)
    ppStep = photobleachPlan(i);

    if v && length(photobleachPlan) > 1 
        fprintf('%s Moving to positoin (x = %.1fmm, y = %.1fmm, z= %.1fmm) #%d of %d\n',...
            datestr(datetime),...
            ppStep.stageCenterX_mm, ...
            ppStep.stageCenterY_mm, ...
            ppStep.stageCenterZ_mm, ...
            i,length(photobleachPlan));
    end
    
    % Move stage to next position
    yOCTStageMoveTo(...
        x0 + ppStep.stageCenterX_mm, ...
        y0 + ppStep.stageCenterY_mm, ...
        z0 + ppStep.stageCenterZ_mm, ...
        v);
    
    % Perform photobleaching of this FOV
    photobleach_lines(...
        ppStep.ptStartInFOV_mm, ...
        ppStep.ptEndInFOV_mm, ...
        json.exposure * ppStep.lineLength_mm, ...
        v, json);

    % Wait before moving the stage to next position to prevent stage
    % motor jamming.
    pause(json.stagePauseBeforeMoving_sec);
end

%% Turn laser diode off
% We set switch to OCT position to prevent light leak
fprintf('%s Turning Laser Diode Off... \n\t(if Matlab is taking more than 1 minute to finish this step, restart hardware and try again)\n',datestr(datetime));

if strcmpi(json.laserToggleMethod,'OpticalSwitch')
	yOCTTurnOpticalSwitch('OCT'); % Set switch position away from photodiode
end
            
% Switch light on, write to screen only for first line
% ThorlabsImagerNET.ThorlabsImager.yOCTTurnLaser(false);  % Version using .NET
yOCTTurnLaser(false); % Version using Matlab directly

fprintf('%s Laser Diode is Off\n',datestr(datetime)); 

%% Finalize
if (v)
    fprintf('%s Finalizing\n',datestr(datetime));
end

%Return stage to original position
yOCTStageMoveTo(x0,y0,z0,v);

ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose(); %Close scanner


%% Working with live laser
function photobleach_lines(ptStart,ptEnd, exposures_sec, v, json)
% This function performes the photobleaching itself. Avoid doing doing any
% calculations in this function as laser beam is on and will continue
% photobleaching.

numberOfLines = size(ptStart,2);
exposures_msec = exposures_sec*1e3;

% Turn on
t_all = tic;
total_time_drawing_line_ms = 0;
if strcmpi(json.laserToggleMethod,'OpticalSwitch')
    % Set optical switch to "on" position
    yOCTTurnOpticalSwitch('photodiode');
else
    % No optical switch, we just keept the diode on, it will createa a phantom line 
end


% Loop over all lines in this FOV
for j=1:numberOfLines
    if (v)
        tic
        fprintf('%s \tPhotobleaching Line #%d of %d. Requested Exposure: %.1fms, ', ...
            datestr(datetime),j,numberOfLines, exposures_msec(j));
    end
  
    ThorlabsImagerNET.ThorlabsImager.yOCTPhotobleachLine( ...
        ptStart(1,j),ptStart(2,j), ... Start X,Y
        ptEnd(1,j),  ptEnd(2,j)  , ... End X,y
        exposures_sec(j),  ... Exposure time sec
        json.nPasses); 
    
    if (v)
        tt_ms = toc()*1e3;
        total_time_drawing_line_ms = total_time_drawing_line_ms + tt_ms;
        fprintf('Measured: %.1fms (+%.1fms)\n',tt_ms,tt_ms-exposures_msec(j));
    end 

end

% Turn laser line off
if strcmpi(json.laserToggleMethod,'OpticalSwitch')
    % Set optical switch to "off" position
    yOCTTurnOpticalSwitch('OCT');
end

if (v)
    t_all_ms = toc(t_all)*1e3;
    time_photodiode_on_no_laser_ms = t_all_ms - total_time_drawing_line_ms;
    if ~strcmpi(json.laserToggleMethod,'OpticalSwitch')
        time_photodiode_on_no_laser_ms = time_photodiode_on_no_laser_ms + json.stagePauseBeforeMoving_sec*1e3;
    end
    fprintf('%s \tTime Photodiode Switch Was On Without Drawing Line: %.1fms\n', ...
            datestr(datetime),time_photodiode_on_no_laser_ms);
end
