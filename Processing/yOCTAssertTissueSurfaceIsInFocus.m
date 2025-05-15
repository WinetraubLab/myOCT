function yOCTAssertTissueSurfaceIsInFocus( ...
    surfacePosition_mm, x_mm, y_mm, acceptableRange_mm, v)
% This function checks the outputs from yOCTScanAndFindTissueSurface and
% asserts that the tissue surface is in focus. It will also explain to user
% how to adjust the z stage such that tissue will be in focus.
%
% INPUTS:
%   surfacePosition_mm: provided by yOCTScanAndFindTissueSurface
%   x_mm: provided by yOCTScanAndFindTissueSurface
%   y_mm: provided by yOCTScanAndFindTissueSurface
%   acceptableRange_mm: how far can tissue surface be from focus position
%       to be considered "good enough". Default: 0.025mm
%   v: verbose flag (true = print, false = silent). Default: False.

%% Input checks

assert(size(surfacePosition_mm,1) == length(y_mm),'surfacePosition_mm first dimension should match y_mm')
assert(size(surfacePosition_mm,2) == length(x_mm),'surfacePosition_mm second dimension should match x_mm')
if ~exist('acceptableRange_mm','var')
    acceptableRange_mm = 0.025;
end
if nargin < 5,  v = false;  end            % verbose OFF by default

%% Compute the average surface distance
surfacePosition_mm = surfacePosition_mm(:);
averageSurfaceDistance_mm = mean(surfacePosition_mm(~isnan(surfacePosition_mm))); % Calculate the average surface distance
if isnan(averageSurfaceDistance_mm)
    error(['No tissue identification possible. Likely the tissue is out of focus below the detection range. ' ...
        'Please manually increase the stage Z position to bring the tissue into focus.']);
end

%% Instruct user how we will change the surface position
if abs(averageSurfaceDistance_mm) > acceptableRange_mm
    if averageSurfaceDistance_mm > 0 % Determine direction of adjustment
        direction = 'increase';   % surface is below focus = raise stage
    else
        direction = 'decrease';   % surface is above focus = lower stage
    end

    % Automatic Z correction
    [x0,y0,z0] = yOCTStageInit();      % query current stage position
    
    try
        yOCTStageMoveTo(NaN, NaN, z0 + averageSurfaceDistance_mm, v);
        warning('Focus‑assert: surface %.3f mm out of range – automatically %sd stage Z by %.3f mm.', ...
                averageSurfaceDistance_mm, direction, abs(round(averageSurfaceDistance_mm,3)));
        if v
            fprintf('%s Stage Z moved from %.3f mm to %.3f mm (OCT coord).\n', ...
                    datestr(datetime), z0, z0 + averageSurfaceDistance_mm);
        end
    catch ME
        warning('Focus‑assert: wanted to %s stage Z by %.3f mm but move failed (%s).', ...
                direction, abs(round(averageSurfaceDistance_mm,3)), ME.message);
    
    end
else
    if v
        fprintf('%s The average distance of the surface (%.3f mm) is within the acceptable range.\n', ...
                datestr(datetime), averageSurfaceDistance_mm);
    end
end
