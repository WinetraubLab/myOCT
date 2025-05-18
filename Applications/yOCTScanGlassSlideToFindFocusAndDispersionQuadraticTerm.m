function [dispersionQuadraticTerm, focusPositionInImageZpix] = ...
    yOCTScanGlassSlideToFindFocusAndDispersionQuadraticTerm(varargin)
% For most OCT applications, we need to find dispersionQuadraticTerm and 
% focusPositionInImageZpix. This script automates this part.
% Before using this script, make sure that the top of the glass slide
% is more or less in focus. Then let it run.
% 
% INPUTS:
%   octProbePath: path to OCT probe
%   dispersionQuadraticTermInitialGuess: initial guess for dispersion
%       value. Units: [nm^2/rad]
%   focusPositionInImageZpixInitialGuess: initial guess for Z position.
%   focusSearchSize_um: We assume that the glass slide is not perfectly in
%       focus, what range should we expect it to be within? Units: microns.
%   tempFolder: path to temporary folder to save OCT volumes.
%   skipHardware: set to true to skip hardware.
%   v: verbose (and visualize) option.

%% Parse inputs

p = inputParser;
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'dispersionQuadraticTermInitialGuess',-1.482e8,@isnumeric);
addParameter(p,'focusPositionInImageZpixInitialGuess',400,@isnumeric);
addParameter(p,'focusSearchSize_um',25,@(x)(isnumeric(x) & x>0));
addParameter(p,'skipHardware',false,@islogical);
addParameter(p,'tempFolder','./TmpOCTVolume/',@ischar);
addParameter(p,'v',true,@islogical);

parse(p,varargin{:});
in = p.Results;

tempFolder = in.tempFolder;
if (tempFolder(end) ~= '\' &&  tempFolder(end) ~= '/')
    tempFolder(end+1) = '/';
end

%% Step #1: Scan multiple depths
if (in.v)
    fprintf('%s Please adjust the OCT focus such that it is at the bottom of the glass silde.\n', datestr(datetime));
end

% Scan some options
pixelSize_um = 1;
yOCTScanTile (...
    tempFolder, ...
    0.05 * [-1, 1], ...
    1e-3 * [-1, 1] * pixelSize_um, ...
    'octProbePath', in.octProbePath, ...
    'pixelSize_um', pixelSize_um, ...
    'skipHardware', in.skipHardware, ...
    'zDepths',1e-3*linspace( ...
        -in.focusSearchSize_um, in.focusSearchSize_um, 5), ...
    'v',in.v  ...
    );

% Load all the scans, find the scan that is in focus
json = awsReadJSON([tempFolder 'ScanInfo.json']);
function atFocusIndex = findScanInFocus()
    atFocusIndex = NaN;
    atFocusIntensity = 0;
    for scanI = 1:length(json.octFolders)
        interf = yOCTLoadInterfFromFile([tempFolder json.octFolders{scanI}]);
        score = mean(abs(interf(:)));
    
        if score > atFocusIntensity
            atFocusIntensity = score;
            atFocusIndex = scanI;
        end
    end
end
atFocusIndex = findScanInFocus();

%% Load the at focus scan
[interf, dim] = yOCTLoadInterfFromFile([tempFolder json.octFolders{atFocusIndex}]);

%% Find dispersion
function e = dispersionErrorFunction(d)
    scan = yOCTInterfToScanCpx(interf, dim, ...
        'dispersionQuadraticTerm', d);

    scan = mean(mean(abs(scan),3),2); % Average along x,y
    e = -max(scan(:)); % Closer the dispersion, the higher the peak.
end
dispersionQuadraticTerm = fminsearch(...
    @dispersionErrorFunction,in.dispersionQuadraticTermInitialGuess);

%% Find focus position
scan = yOCTInterfToScanCpx(interf, dim, ...
        'dispersionQuadraticTerm', dispersionQuadraticTerm);
scanMean = mean(mean(abs(scan),3),2); % Average along x,y

% Remove z depths that are too far from the initial guess
zToInclude = ones(size(scanMean),'logical');
zToInclude(round(1:(in.focusPositionInImageZpixInitialGuess-200))) = 0;
zToInclude(round((in.focusPositionInImageZpixInitialGuess+200):end)) = 0;
scanMean(~zToInclude) = 0;

% Focus is where the peak is achived
[~,focusPositionInImageZpix] = max(scanMean);

%% Plot
if ~in.v
    return; % No plotting needed
end

figure(223)
imagesc(log(squeeze(scan(:,:,1))));
colormap gray;
yline(focusPositionInImageZpix, 'r--');
title(sprintf('dispersionQuadraticTerm=%.2g, focusPositionInImageZpix=%d',...
    dispersionQuadraticTerm,focusPositionInImageZpix));
xlabel('x [pix]');
ylabel('z [pix]');

end
