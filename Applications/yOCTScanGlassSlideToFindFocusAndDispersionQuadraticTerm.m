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

% This helper function scans to find focus. It outputs interfs
% (lambda,x,zDepth), and zDepths_mm for the positions that the scan was
% conducted. atFocusIndex is the index of the focus.
function [interfs, zDepths_mm, atFocusIndex, dim] = scanToFindFocus()
    % Parameters
    nuberOfPixels = 100;
    bestZ_mm = 0; % Initialize to what the user set
    nSamplesInRange = 8; % Use even number to prevent scanning the same spot

    % Build range as a cascaede of zooming in options
    range_um(1) = in.focusSearchSize_um;
    step_um = @(range)(range*2/(nSamplesInRange-1)); 
    while(step_um(step_um(range_um(end)))>1)
        range_um(end+1) = round(step_um(range_um(end))*1.2); %#ok<AGROW>
    end
    range_um(end+1) = 1*(nSamplesInRange-1)/2;% Last range has 1um step size
    
    % Initalize collection
    zDepths_mm = [];
    interfs = [];

    % Scan some options
    for i=1:length(range_um)
        if (in.v)
            fprintf('Best Focus Positon: %.0fum. Scanning [%.1fum, %.1fum]\n', ...
                bestZ_mm*1e3, -range_um(i), range_um(i));
        end
        yOCTScanTile (...
            tempFolder, ...
            1e-3 * [-1, 1] * pixelSize_um * nuberOfPixels/2, ...
            1e-3 * [-1, 1] * pixelSize_um, ...
            'octProbePath', in.octProbePath, ...
            'pixelSize_um', pixelSize_um, ...
            'skipHardware', in.skipHardware, ...
            'zDepths',bestZ_mm + 1e-3 * ...
                linspace(-range_um(i),range_um(i), nSamplesInRange), ...
            'v',in.v  ...
            );
        
        % Load all the scans, find the scan that is in focus
        json = awsReadJSON([tempFolder 'ScanInfo.json']);
        atFocusIndex = NaN;
        atFocusIntensity = 0;
        for scanI = 1:length(json.octFolders)
            [interf, dim] = yOCTLoadInterfFromFile(...
                [tempFolder json.octFolders{scanI}], 'YFramesToProcess',1);
            score = mean(abs(interf(:)));
            
            % Collect data
            if isempty(interfs)
                interfs = interf(:,:,1);
            else
                interfs(:,:,size(interfs,3)+1) = interf(:,:,1); %#ok<AGROW>
            end
            zDepths_mm(end+1) = json.zDepths(scanI); %#ok<AGROW>
        
            if score > atFocusIntensity
                atFocusIntensity = score;
                atFocusIndex = size(interfs,3);
            end
        end

        % Update best focus position
        bestZ_mm = zDepths_mm(atFocusIndex);
    end % Loop around

    % Sort output
    [~, ind] = sort(zDepths_mm);
    zDepths_mm = zDepths_mm(ind);
    interfs = interfs(:,:,ind);
    atFocusIndex = find(bestZ_mm==zDepths_mm,1,'first');
end
[interfs, zDepths_mm, atFocusIndex, dim] = scanToFindFocus();
interfAtFocus = squeeze(interfs(:,:,atFocusIndex));

%% Find dispersion
function e = dispersionErrorFunction(d)
    scan = yOCTInterfToScanCpx(interfAtFocus, dim, ...
        'dispersionQuadraticTerm', d);

    scan = mean(mean(abs(scan),3),2); % Average along x,y
    e = -max(scan(:)); % Closer the dispersion, the higher the peak.
end
dispersionQuadraticTerm = fminsearch(...
    @dispersionErrorFunction,in.dispersionQuadraticTermInitialGuess);

%% Convert all interfs to scans
scans = [];
for ii=1:length(zDepths_mm)
    scan1 = yOCTInterfToScanCpx(interfs(:,:,ii), dim, ...
        'dispersionQuadraticTerm', dispersionQuadraticTerm);
    scan1 = mean(abs(scan1),3);
    if isempty(scans)
        scans = scan1;
    else
        scans(:,:,end+1) = scan1; %#ok<AGROW>
    end
end
scanAtFocus = squeeze(scans(:,:,atFocusIndex));


%% Find focus position
scanMean = mean(scanAtFocus,2); % Average along x,y

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

% Plot final result
figure(223)
imagesc(log(scanAtFocus));
colormap gray;
yline(focusPositionInImageZpix, 'r--');
title(sprintf('dispersionQuadraticTerm=%.4g, focusPositionInImageZpix=%d',...
    dispersionQuadraticTerm,focusPositionInImageZpix));
xlabel('x [pix]');
ylabel('z [pix]');

% Identify which z is at the focus position
figure(224);
for ii = 1:length(zDepths_mm)
    subplot(1,length(zDepths_mm),ii)

    imagesc(log(squeeze(scans(:,:,ii))));
    colormap gray;
    if ii == atFocusIndex
        title(['Estimated' newline 'Focus']);
    else
        title(sprintf('%.0f\\mum',1e3*(zDepths_mm(ii)-zDepths_mm(atFocusIndex))));
    end

    % Turn off tick labels if not needed
    set(gca, 'XTickLabel', []);
    if ii ~= 1
        set(gca, 'YTickLabel', []);
    end
end
end
