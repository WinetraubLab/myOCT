function json = yOCTPhotobleachTile(varargin)
% This function photobleaches a pattern, the pattern can be bigger than the
% FOV of the scanner and then the script wii tile around to stitch together
% multiple scans.
% INPUTS:
%   ptStart: point(s) to strat line x and y (in mm). Can be 2Xn matrix for
%       drawing multiple lines. Line position is relative to current's stage position and relative to the opical axis of the lens 
%   ptEnd: corresponding end point (x,y), in mm
% NAME VALUE INPUTS:
%   Parameter               Default Value   Notes
% Probe defenitions:
%   octProbePath            'probe.ini'     Where is the probe.ini is saved to be used
% Photobleaching Parameters:
%   z                       0               Photobleaching depth (compared to corrent position in mm). 
%                                           Can be array for multiple depths. Use array for high NA lens that require photobleach in serveral depths.
%                                           This option will draw the same lines defined in ptStart and ptEnd in multiple dpeths. 
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
FOV = json.FOV;

v = json.v;
json = rmfield(json,'v');

% Stage pause before moving
json.stagePauseBeforeMoving_sec = 0.5;

% Check number of passes and exposure
assert(isscalar(json.nPasses), 'Only 1 nPasses is permitted for all lines');
assert(isscalar(json.exposure), 'Only 1 exposure is permitted for all lines');
    
%% Pre processing

if isempty(json.ptStart) || isempty(json.ptEnd)
	% Nothing to photobleach
	return;
end

% Apply Enable Zone
if isa(enableZone,'function_handle')
    [ptStart,ptEnd] = yOCTApplyEnableZone(json.ptStart, json.ptEnd, enableZone, 10e-3);
    json.ptStart = ptStart;
    json.ptEnd = ptEnd;
end

%% Initial distance check
dPerAxis = json.ptStart - json.ptEnd;
d = sqrt(sum((dPerAxis).^2,1));
if not(any(d>json.minLineLength))
    warning('No lines to photobleach, exit');
    return;
end

%% Find what FOVs & lines to photobleach

% Find what FOVs should we go to
minX = min([json.ptStart(1,:) json.ptEnd(1,:)]);
maxX = max([json.ptStart(1,:) json.ptEnd(1,:)]);
minY = min([json.ptStart(2,:) json.ptEnd(2,:)]);
maxY = max([json.ptStart(2,:) json.ptEnd(2,:)]);
xCenters = unique([0:(-FOV(1)):(minX-FOV(1)) 0:FOV(1):(maxX+FOV(1))]);
yCenters = unique([0:(-FOV(2)):(minY-FOV(1)) 0:FOV(1):(maxY+FOV(2))]);

% Check if there are lines that start and finish close to the edges of FOV.
% If thereare, they may not be drawn at all and we should warn the user
[xedg,yedg]=meshgrid(...
    [xCenters-FOV(1)/2, xCenters(end)+FOV(1)/2], ...
    [yCenters-FOV(2)/2, yCenters(end)+FOV(2)/2]);
xedg = xedg(:);
yedg = yedg(:);
isLineTooCloseToEdge = zeros(1,size(json.ptStart,2),'logical');
for i=1:length(xedg)
    pt0 = [xedg(i); yedg(i)];
    isLineTooCloseToEdge = isLineTooCloseToEdge | ...
        sqrt(sum((json.ptStart-pt0).^2))<json.bufferZoneWidth | ...
        sqrt(sum((json.ptEnd  -pt0).^2))<json.bufferZoneWidth;
end
if (any(isLineTooCloseToEdge))
    ii = find(isLineTooCloseToEdge,1,'first');
    warning(['Photobleaching line from (%.1fmm, %.1fmm) to (%.1fmm, %.1fmm).\n' ...
        'This line is very close to lens''s edge and might not show up.\n' ...
        'Please move line inside lens''s FOV'],...
        json.ptStart(1,ii), json.ptStart(2,ii),json.ptEnd(1,ii), json.ptEnd(2,ii));
end

% Generate what lines we should draw for each center
[xcc,ycc]=meshgrid(xCenters,yCenters);
xcc = xcc(:); ycc = ycc(:);
ptStartcc = cell(length(xcc),1);
ptEndcc = ptStartcc;
lineLengths = ptEndcc;
for i=1:length(ptStartcc)    
    [ptStart,ptEnd] = yOCTApplyEnableZone(json.ptStart, json.ptEnd, ...
        @(x,y)( ...
            abs(x-xcc(i))<FOV(1)/2-json.bufferZoneWidth/2 & ...
            abs(y-ycc(i))<FOV(2)/2-json.bufferZoneWidth/2 ) ...
        , json.enableZoneAccuracy);

    % Compute line length
    dPerAxis = ptStart - ptEnd;
    d = sqrt(sum((dPerAxis).^2,1));
    
    % Remove lines that are too short to photobleach
    ptStart(:,d<json.minLineLength) = [];
    ptEnd(:,d<json.minLineLength) = [];
 
    % Double check we don't have lines that are too long
    if ~isempty(dPerAxis)
        if any( abs(dPerAxis(1,:))>FOV(1) | abs(dPerAxis(2,:))>FOV(2) )
            error('One (or more) of the photobleach lines is longer than the allowed size by lens, this might cause photobleaching errors!');
        end
    end
    
    % Save lines
    ptStartcc{i} = ptStart;
    ptEndcc{i} = ptEnd;
	lineLengths{i} = d;
end

% Remove empty slots
em = cellfun(@isempty,ptStartcc);
ptStartcc(em) = [];
ptEndcc(em) = [];
xcc(em) = [];
ycc(em) = [];
lineLengths(em)=[];

%% Add photonleach instructions to json
clear photobleachInstructions;

for i=1:length(xcc)
    photobleachInstructions(i).stageCenterX = xcc(i);
    photobleachInstructions(i).stageCenterY = ycc(i);
    photobleachInstructions(i).linesPhotobleachedStart = ptStartcc{i};
    photobleachInstructions(i).linesPhotobleachedEnd = ptEndcc{i};
end
json.photobleachInstructions = photobleachInstructions;

%% Estimate photobleach time
totalLineLength = sum(sum([lineLengths{:}])); % mm
estimatedPhotobleachTime_sec = totalLineLength*json.exposure; % sec

%% Plot the pattern
if json.plotPattern
    colors = num2cell(winter(length(xcc)),2);
    
    figure;
    for tileI = 1:length(ptStartcc)
        % Draw the phtobleach panel
        rectangle('Position',...
            [-FOV(1)/2+xcc(tileI) -FOV(2)/2+ycc(tileI) FOV(1) FOV(2)],...
            'EdgeColor',[0.5 0.5 0.5]);
        hold on;
        
        % Draw the lines that are photobleached
        s = ptStartcc{tileI};
        e = ptEndcc{tileI};
        s_x = s(1,:);
        s_y = s(2,:);
        e_x = e(1,:);
        e_y = e(2,:);
        for plotI = 1:length(s_x)
           plot([s_x(plotI) e_x(plotI)],[s_y(plotI) e_y(plotI)],'Color',colors{tileI});
        end
        
    end
    hold off;
    axis equal;
    axis ij; % Match coordinate system: https://docs.google.com/presentation/d/1tOod76WvhvOuByo-K81YB4b3QjRq-6A5j2ztS_ANSNo/edit#slide=id.g2812f1bd1d1_0_115
    grid on;
    xlabel('x[mm]');
    ylabel('y[mm]');
	title(sprintf('Photobleach Pattern\nEstimated Time: %.0f minutes',ceil(estimatedPhotobleachTime_sec/60)));
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

ptStart = ptStartcc{1} - [xcc(1);ycc(1)];
ptEnd   = ptEndcc{1}   - [xcc(1);ycc(1)];
exposures_sec = json.exposure*sqrt(sum( (ptStart - ptEnd).^2));
     
ThorlabsImagerNET.ThorlabsImager.yOCTPhotobleachLine( ...
    ptStart(1,1),ptStart(2,1), ... Start X,Y
    ptEnd(1,1),  ptEnd(2,1)  , ... End X,y
    exposures_sec(1),  ... Exposure time sec
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

% Loop over FOVs
for i=1:length(xcc)
    
    % Loop over depths in the same FOV
    for iZ=1:length(json.z)
        if (v && (length(xcc) > 1 || length(json.z) > 1) )
            fprintf('%s Moving to positoin (x = %.1fmm, y = %.1fmm, z= %.1fmm) #%d of %d\n',...
                datestr(datetime),xcc(i),ycc(i),json.z(iZ),i,length(xcc));
        end
    
        % Move stage to next position
        yOCTStageMoveTo(x0+xcc(i),y0+ycc(i),z0+json.z(iZ),v);
        
        %Find lines to photobleach, center along current position of the stage
        ptStart = ptStartcc{i} - [xcc(i);ycc(i)];
        ptEnd   = ptEndcc{i}   - [xcc(i);ycc(i)];
        exposures_sec = json.exposure*sqrt(sum( (ptStart - ptEnd).^2));
        
        % Perform photobleaching of this FOV
        photobleach_lines(ptStart,ptEnd, exposures_sec, v, json);
 
        % Wait before moving the stage to next position to prevent stage
        % motor jamming.
        pause(json.stagePauseBeforeMoving_sec);
    end
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
