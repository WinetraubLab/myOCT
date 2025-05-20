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

nIndexOfRefraction = 1.33;

parse(p,varargin{:});
in = p.Results;

tempFolder = in.tempFolder;
if (tempFolder(end) ~= '\' &&  tempFolder(end) ~= '/')
    tempFolder(end+1) = '/';
end

%% Scan multiple depths to find focus
if (in.v)
    fprintf('%s Please adjust the OCT focus such that it is at glass silde interface, closest to the tissue.\n', datestr(datetime));
end

% This helper function scans to find focus. It outputs interfs
% (lambda,x,zDepth), and zDepths_mm for the positions that the scan was
% conducted. atFocusIndex is the index of the focus.
function [interfs, zDepths_mm, atFocusIndex, dim] = scanToFindFocus()
    % Parameters
    pixelSize_um = 0.1;
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
                bestZ_mm*1e3, bestZ_mm*1e3-range_um(i), bestZ_mm*1e3+range_um(i));
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
        'dispersionQuadraticTerm', d, 'n', nIndexOfRefraction);

    scan = mean(mean(log(abs(scan)),3),2); % Average along x,y
    e = -max(scan(:)); % Closer the dispersion, the higher the peak.
end
dispersionQuadraticTerm = fminsearch(...
    @dispersionErrorFunction, ...
    in.dispersionQuadraticTermInitialGuess);
if (in.v)
    fprintf('dispersionQuadraticTerm = %.4g\n',dispersionQuadraticTerm)
end

%% Convert all interfs to scans
scans = [];
for ii=1:length(zDepths_mm)
    [scan1,dim] = yOCTInterfToScanCpx(interfs(:,:,ii), dim, ...
        'dispersionQuadraticTerm', dispersionQuadraticTerm, 'n', nIndexOfRefraction);
    scan1 = mean(abs(scan1),3);
    if isempty(scans)
        scans = scan1;
    else
        scans(:,:,end+1) = scan1; %#ok<AGROW>
    end
end
scanAtFocus = squeeze(scans(:,:,atFocusIndex));

%% Find focus position
scanMean = mean(log(scanAtFocus),2); % Average along x,y

% Remove z depths that are too far from the initial guess
zToInclude = ones(size(scanMean),'logical');
zToInclude(round(1:(in.focusPositionInImageZpixInitialGuess-200))) = 0;
zToInclude(round((in.focusPositionInImageZpixInitialGuess+200):end)) = 0;
scanMean(~zToInclude) = 0;

% Focus is where the peak is achived
[~,focusPositionInImageZpix] = max(scanMean);

% Sanity check, make sure that Z doesn't change a lot along the scan
% In theory, the scan should be very small thus z shouldn't change
pos = alignZ(log(scanAtFocus));
assert(max(abs(pos-focusPositionInImageZpix)) < 2, 'Check focusPositionInImageZpix against scan failed');

%% Plot final plot
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

%% Plot Identify which z is at the focus position
figure(224);
peakPixel = zeros(size(zDepths_mm));
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

    % Capture maximum pixel
    [~,peakPixel(ii)] = max(mean(log(squeeze(scans(:,:,ii))),2));
end

% Compute the relationship between peakPixel position and depth
p = polyfit(peakPixel,zDepths_mm,1);
zPixelSizeByPolyFit_um = abs(p(1)*1e3);
zPixelSizeFromDim_um = diff(dim.z.values(1:2));

if abs(zPixelSizeFromDim_um/zPixelSizeByPolyFit_um-1) > 0.02
    adjustedN = zPixelSizeFromDim_um/zPixelSizeByPolyFit_um*nIndexOfRefraction;
    warning('Index of refreaction is probably not %.2f.\nZ pixel size by fiting movement: %.2fum.\nZ pixel size by n: %.2fum.\nRecommended n=%.2f',...
        nIndexOfRefraction,zPixelSizeByPolyFit_um,zPixelSizeFromDim_um,...
        adjustedN);

    if in.v
        figure(19)
        plot(peakPixel,zDepths_mm*1e3,'o',peakPixel,polyval(p,peakPixel)*1e3,'-');
        xlabel('Peak Z Position [pix]');
        ylabel('Stage Z Position [um]');
        legend('Data',sprintf('Fit, n=%.2f',adjustedN));
        grid on;
        title('Peak Position [pixels] vs Stage Position [um]');
    end
end

%% Plot dispersion 

% Compute scans on a few dispersion values
dValues = unique([dispersionQuadraticTerm, linspace(dispersionQuadraticTerm*0.96, dispersionQuadraticTerm*1.04,4)]);
[~,ii] = sort(abs(dValues));
dValues = dValues(ii);
intensities = zeros(size(scans,1),length(dValues));
for ii = 1:length(dValues)
    scan = yOCTInterfToScanCpx(interfAtFocus, dim, ...
        'dispersionQuadraticTerm', dValues(ii), 'n', nIndexOfRefraction);
    intensities(:,ii) = mean(mean(log(abs(scan)),3),2);
end

% Find key dispersion values
iSame = find(dValues==dispersionQuadraticTerm,1,'first');

% Asign color to each graph
col = zeros(size(dValues));
col(abs(dValues) > abs(dispersionQuadraticTerm)) = 1;
col(abs(dValues) < abs(dispersionQuadraticTerm)) = -1;

i1P = find(col==1,1,'first');
i1N = find(col==-1,1,'last');

% Align z to match
[focusAlignment] = alignZ(intensities,intensities(:,iSame)); % Align z to template
focusAlignment = focusAlignment-mean(focusAlignment);
zI = 1:size(intensities,1);

% Plot all options
figure(225);
plot(zI+focusAlignment(iSame),intensities(:,iSame),'r','LineWidth',2)
hold on;
plot(zI+focusAlignment(i1P),intensities(:,i1P),'g','LineWidth',2)
plot(zI+focusAlignment(i1N),intensities(:,i1N),'b','LineWidth',2)
for ii=find(col==1)
    plot(zI+focusAlignment(ii),intensities(:,ii),'g')
end
for ii=find(col==-1)
    plot(zI+focusAlignment(ii),intensities(:,ii),'b')
end
plot(zI+focusAlignment(iSame),intensities(:,iSame),'r','LineWidth',2)
hold off;
xlabel('Z [pix]');
ylabel('Log Intensity');
legend('Optimal Dispersion', 'Above Optimal Dispoersion', 'Below Optimal Dispersion');
xlim(focusPositionInImageZpix + [-6 6]);
grid on;
if col(1) == 1
    s1 = 'green';
    s2 = 'blue';
else
    s1 = 'blue';
    s2 = 'green';
end
title(sprintf('%.4g (%s) to %.4g (%s)',dValues(1),s1,dValues(end),s2));

end

function [pos, width] = alignZ(scan, template)
    zI = 1:size(scan,1); zI = zI(:);
    
    pos = zeros(1,size(scan,2));
    width = pos;
    for xI = 1:length(pos)
        s = scan(:, xI);
        [~, maxIdZ] = max(s);
        maxIdZEnv = maxIdZ + (-5:5); maxIdZEnv=maxIdZEnv(:);

        if ~exist('template','var') % Gaussian template
            model = @(x)(x(1)*exp( -(zI(maxIdZEnv)-x(2)).^2/(2*x(3)^2) ) + x(4));
            x0 = [max(s)-min(s(maxIdZEnv)),maxIdZ,1,min(s(maxIdZEnv))];
        else
            % Use the template vector
            model = @(x)(interp1(zI, template, maxIdZEnv+x(2), 'linear'));
            x0 = [0,0,0];
        end
        
        a = fminsearch(@(x)(mean( (model(x)-s(maxIdZEnv)).^2 )),x0);
        
        pos(xI) = a(2);
        %plot(zI(maxIdZEnv),[s(maxIdZEnv) model(a)]);
    end
    %plot(pos);
end