function photobleachPlan = yOCTPhotobleachTile_createPlan(...
    ptStart_mm, ptEnd_mm, z_mm, FOV_mm, minLineLength_mm, bufferZoneWidth_mm,...
    enableZoneAccuracy_mm, enableZone)
% This is a helper function to yOCTPhotobleachTile, it accepts the start
% and end of each line and creates a photobleach plan: dividing up the
% lines by FOV and depth.
%
% INPUTS:
%   ptStart_mm: start position of each line, see yOCTPhotobleachTile.
%   ptEnd_mm: end position of each line, see yOCTPhotobleachTile.
%   z_mm: the depth in which each line ptStart_mm->ptEnd_mm is
%       photobleached. See yOCTPhotobleachTile.
%   FOV_mm: lens's FOV [x, y].
%   minLineLength_mm: minimal length of a photobleach line, see 
%       yOCTPhotobleachTile.
%   bufferZoneWidth_mm: don't allow photobleaching at the very end of an
%       FOV to prevent lines overlap. See yOCTPhotobleachTile.
%   enableZoneAccuracy: see yOCTPhotobleachTile.
%   enableZone: see yOCTPhotobleachTile.

photobleachPlan = [];

%% Set default values for testing capabilities

if ~exist('FOV_mm','var')
    FOV_mm = [0.5 0.5];
end
if ~exist('minLineLength_mm','var')
    minLineLength_mm = 10e-3;
end
if ~exist('bufferZoneWidth_mm','var')
    bufferZoneWidth_mm = 10e-3;
end
if ~exist('enableZoneAccuracy','var')
    enableZoneAccuracy_mm = 5e-3;
end
if ~exist('enableZone','var')
    enableZone = NaN;
end

if isscalar(z_mm)
    % Only one depth was provided, make sure depth is assigned for each
    % line.
    z_mm = ones(1,size(ptStart_mm,2))*z_mm;
else
    z_mm = z_mm(:)';
end

%% Add z:
ptStart_mm = [ptStart_mm; z_mm];
ptEnd_mm = [ptEnd_mm; z_mm];

%% Initial input check
if any(size(ptStart_mm) ~= size(ptEnd_mm))
    error('Check input points array, it should be same size');
end

if isempty(ptStart_mm) || isempty(ptEnd_mm)
	% Nothing to photobleach
	return;
end

% Apply Enable Zone
if isa(enableZone,'function_handle')
    [ptStart_mm, ptEnd_mm] = yOCTApplyEnableZone(ptStart_mm, ptEnd_mm, ...
        @(x,y,z)(enableZone(x,y)), 10e-3);
end

% Check if any remaning photobleach lines have meaningful length
dPerAxis = ptStart_mm - ptEnd_mm;
d = sqrt(sum((dPerAxis).^2,1));
if not(any(d>minLineLength_mm))
    warning('No lines to photobleach, exit');
    return;
end

%% Split the photobleach task to FOVs

function [xCenters, yCenters] = splitLinesToFOVs()
    % Find what FOVs should we go to
    minX = min([ptStart_mm(1,:) ptEnd_mm(1,:)]);
    maxX = max([ptStart_mm(1,:) ptEnd_mm(1,:)]);
    minY = min([ptStart_mm(2,:) ptEnd_mm(2,:)]);
    maxY = max([ptStart_mm(2,:) ptEnd_mm(2,:)]);
    xCenters = unique([0:(-FOV_mm(1)):(minX-FOV_mm(1)) 0:FOV_mm(1):(maxX+FOV_mm(1))]);
    yCenters = unique([0:(-FOV_mm(2)):(minY-FOV_mm(1)) 0:FOV_mm(1):(maxY+FOV_mm(2))]);
    
    % Check if there are lines that start and finish close to the edges of FOV.
    % If thereare, they may not be drawn at all and we should warn the user
    [xedg,yedg]=meshgrid(...
        [xCenters-FOV_mm(1)/2, xCenters(end)+FOV_mm(1)/2], ...
        [yCenters-FOV_mm(2)/2, yCenters(end)+FOV_mm(2)/2]);
    xedg = xedg(:);
    yedg = yedg(:);
    isLineTooCloseToEdge = zeros(1,size(ptStart_mm,2),'logical');
    for ii=1:length(xedg)
        pt0 = [xedg(ii); yedg(ii)];
        isLineTooCloseToEdge = isLineTooCloseToEdge | ...
            sqrt(sum((ptStart_mm(1:2,:)-pt0).^2))<bufferZoneWidth_mm | ...
            sqrt(sum((ptEnd_mm(1:2,:)  -pt0).^2))<bufferZoneWidth_mm;
    end

    % Some lines are too close, warn user
    if (any(isLineTooCloseToEdge))
        ii = find(isLineTooCloseToEdge,1,'first');
        warning(['Photobleaching line from (%.1fmm, %.1fmm) to (%.1fmm, %.1fmm).\n' ...
            'This line is very close to lens''s edge and might not show up.\n' ...
            'Please move line inside lens''s FOV'],...
            ptStart_mm(1,ii), ptStart_mm(2,ii),ptEnd_mm(1,ii), ptEnd_mm(2,ii));
    end
end
[xCenters, yCenters] = splitLinesToFOVs();

%% Create a grid of FOVs and assign each line to its grid

function [xcc, ycc, ptStartcc, ptEndcc, lineLengths] = assignToGrid()
    % Generate what lines we should draw for each center
    [xcc,ycc]=meshgrid(xCenters,yCenters);
    xcc = xcc(:); ycc = ycc(:);
    ptStartcc = cell(length(xcc),1);
    ptEndcc = ptStartcc;
    lineLengths = ptEndcc;
    for ii=1:length(ptStartcc)    
        [ptStartInFOV,ptEndInFOV] = yOCTApplyEnableZone(ptStart_mm, ptEnd_mm, ...
            @(x,y,z)( ...
                abs(x-xcc(ii))<FOV_mm(1)/2-bufferZoneWidth_mm/2 & ...
                abs(y-ycc(ii))<FOV_mm(2)/2-bufferZoneWidth_mm/2 ) ...
            , enableZoneAccuracy_mm);
    
        % Compute line length
        dPerAxis = ptStartInFOV - ptEndInFOV;
        d = sqrt(sum((dPerAxis).^2,1));
        
        % Remove lines that are too short to photobleach
        ptStartInFOV(:,d<minLineLength_mm) = [];
        ptEndInFOV(:,d<minLineLength_mm) = [];
     
        % Double check we don't have lines that are too long
        if ~isempty(dPerAxis)
            if any( abs(dPerAxis(1,:))>FOV_mm(1) | abs(dPerAxis(2,:))>FOV_mm(2) )
                error('One (or more) of the photobleach lines is longer than the allowed size by lens, this might cause photobleaching errors!');
            end
        end
        
        % Save lines
        ptStartcc{ii} = ptStartInFOV;
        ptEndcc{ii} = ptEndInFOV;
	    lineLengths{ii} = d;
    end
end
[xcc, ycc, ptStartcc, ptEndcc, lineLengths] = assignToGrid();

%% Create the photobleach instructions array
clear photobleachPlan;
% Photobleach plan defines 
% 1) How to set the stage centers.
% 2) What lines to photobleach on those positions.

for i=1:length(xcc)
    clear ppStep;

    % Make sure that some photobleach lines exist for this step
    if isempty(ptStartcc{i})
        continue; % No photobleach lines
    end

    % Define the XY center of the step
    ppStep.stageCenterX_mm = xcc(i);
    ppStep.stageCenterY_mm = ycc(i);

    % For each XY, find how many z positions for lines are
    z = ptStartcc{i}(3,:);
    uniqueZ = unique(z);
    for zI=1:length(uniqueZ)
        ppStep.stageCenterZ_mm = uniqueZ(zI);
        linesInThisDepthI = ptStartcc{i}(3,:)==uniqueZ(zI);

        ppStep.ptStartInFOV_mm = ptStartcc{i}(1:2,linesInThisDepthI) - [xcc(i);ycc(i)];
        ppStep.ptEndInFOV_mm = ptEndcc{i}(1:2,linesInThisDepthI) - [xcc(i);ycc(i)];
        ppStep.lineLength_mm = lineLengths{i}(linesInThisDepthI);
        ppStep.performTilePhotobleaching = true;

        if ~exist('photobleachPlan','var')
            photobleachPlan = ppStep;
        else
            photobleachPlan(end+1) = ppStep; %#ok<AGROW>
        end
    end
end

if ~exist('photobleachPlan','var')
    photobleachPlan=[];
end
end