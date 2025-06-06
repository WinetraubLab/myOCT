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
%   tissueRefractiveIndex: Refractive index of tissue.
%   skipHardware: set to true to skip hardware.
%   v: verbose (and visualize) option.

%% Parse inputs

p = inputParser;
addParameter(p,'octProbePath','probe.ini',@ischar);
addParameter(p,'dispersionQuadraticTermInitialGuess',-1.482e8,@isnumeric);
addParameter(p,'focusPositionInImageZpixInitialGuess',400,@isnumeric);
addParameter(p,'focusSearchSize_um',25,@(x)(isnumeric(x) & x>0));
addParameter(p,'skipHardware',false,@islogical);
addParameter(p,'tissueRefractiveIndex',1.4);
addParameter(p,'tempFolder','./TmpOCTVolume/',@ischar);
addParameter(p,'v',true,@islogical);

parse(p,varargin{:});
in = p.Results;

tempFolder = in.tempFolder;
if (tempFolder(end) ~= '\' &&  tempFolder(end) ~= '/')
    tempFolder(end+1) = '/';
end
in.tempFolder = tempFolder;

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
    range_um(1) = 0; % First range is just the user selected focus
    range_um(2) = in.focusSearchSize_um;
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
        scanDepths_um = unique(round(bestZ_mm*1e3 + linspace(-range_um(i),range_um(i), nSamplesInRange)));
        if (in.v)
            fprintf('Scanning [%.0fum, %.0fum]\n', ...
                scanDepths_um(1),scanDepths_um(end));
        end
        yOCTScanTile (...
            tempFolder, ...
            1e-3 * [-1, 1] * pixelSize_um * nuberOfPixels/2, ...
            1e-3 * [-1, 1] * pixelSize_um, ...
            'octProbePath', in.octProbePath, ...
            'pixelSize_um', pixelSize_um, ...
            'skipHardware', in.skipHardware, ...
            'zDepths', scanDepths_um*1e-3, ... zDepths are in mm
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

        if in.v && i >= 2
            fprintf('Best Focus Positon: %.0fum. ', bestZ_mm*1e3);
        end
    end % Loop around
    if (in.v)
        fprintf('\n')
    end

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
        'dispersionQuadraticTerm', d, 'n', in.tissueRefractiveIndex);

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
        'dispersionQuadraticTerm', dispersionQuadraticTerm, 'n', in.tissueRefractiveIndex);
    scan1 = mean(abs(scan1),3);
    if isempty(scans)
        scans = scan1;
    else
        scans(:,:,end+1) = scan1; %#ok<AGROW>
    end
end
scanAtFocus = squeeze(scans(:,:,atFocusIndex));

%% Find focus position for the scan in focus
function focusZ_pix = findPeakPixel(scan, initialGuess)
    scanMean = squeeze(mean(log(scan),2)); % Average along x,y

    % Remove z depths that are too far from the initial guess
    zToInclude = ones(size(scanMean),'logical');
    zToInclude(round(1:(initialGuess-200))) = 0;
    zToInclude(round((initialGuess+200):end)) = 0;
    scanMean(~zToInclude) = 0;

    % Focus is where the peak is achived
    [~,focusZ_pix] = max(scanMean);
end

% Focus position is the same as pixel position in the image that is in focus
focusPositionInImageZpix = findPeakPixel(...
    scans(:,:,atFocusIndex), in.focusPositionInImageZpixInitialGuess);
if (in.v)
    fprintf('focusPositionInImageZpix = %d\n',focusPositionInImageZpix)
end

% Sanity check, make sure that Z doesn't change a lot along the scan
% In theory, the scan should be very small thus z shouldn't change
pos = alignZ(log(scanAtFocus));
assert(prctile(abs(pos-focusPositionInImageZpix),95) < 2, 'Check focusPositionInImageZpix against scan failed');

%% Compute the slide interface pixel and depth scan
% This relationship validates that z pixel size is the same.

% Estimate peak position
peakPosition_pix = zeros(size(zDepths_mm));
for ii=1:length(peakPosition_pix)
    peakPosition_pix(ii) = findPeakPixel(...
        scans(:,:,ii), focusPositionInImageZpix);
end

% Linear fit to extract pixel size
peakPositionVsDepthP = polyfit(peakPosition_pix,zDepths_mm,1);
zPixelSizeByPolyFit_um = abs(peakPositionVsDepthP(1)*1e3);
zPixelSizeFromDim_um = diff(dim.z.values(1:2));

% Check the two figures match
adjustedN = zPixelSizeFromDim_um/zPixelSizeByPolyFit_um*in.tissueRefractiveIndex;
if abs(zPixelSizeFromDim_um/zPixelSizeByPolyFit_um-1) > 0.05
    warning('tissueRefractiveIndex is probably not %.2f.\nZ pixel size by fiting movement: %.2fum.\nZ pixel size by n: %.2fum.\nRecommended n=%.2f',...
        in.tissueRefractiveIndex,zPixelSizeByPolyFit_um,zPixelSizeFromDim_um,...
        adjustedN);
end

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
saveas(gcf, [in.tempFolder 'final_plot.png']);

%% Plot Identify which z is at the focus position
figure(224);
set(gcf, 'Units', 'pixels', 'Position', [100 100 1600 400]);
for ii = 1:length(zDepths_mm)
    subplot(1,length(zDepths_mm),ii)

    imagesc(log(squeeze(scans(:,:,ii))));
    colormap gray;
    if ii == atFocusIndex
        title(sprintf('Estimated\nFocus\n%.0f\\mum',1e3*zDepths_mm(ii)));
    else
        title(sprintf('%.0f\\mum',1e3*zDepths_mm(ii)));
    end

    % Turn off tick labels if not needed
    set(gca, 'XTickLabel', []);
    if ii ~= 1
        set(gca, 'YTickLabel', []);
    end
end
saveas(gcf, [in.tempFolder 'focus_position.png']);

figure(19)
plot(peakPosition_pix,zDepths_mm*1e3,'o',...
    peakPosition_pix,polyval(peakPositionVsDepthP,peakPosition_pix)*1e3,'-');
xlabel('Peak Z Position [pix]');
ylabel('Stage Z Position [um]');
legend('Data',sprintf('Fit, n=%.2f',adjustedN));
grid on;
title('Peak Position [pixels] vs Stage Position [um]');
saveas(gcf, [in.tempFolder 'pixel_size_estimation.png']);


%% Plot dispersion 

% Compute scans on a few dispersion values
dValues = unique([dispersionQuadraticTerm, linspace(dispersionQuadraticTerm*0.95, dispersionQuadraticTerm*1.05,6)]);
[~,ii] = sort(abs(dValues));
dValues = dValues(ii);
scansDisp1 = zeros(size(scans,1),size(scans,2),length(dValues));
scansDisp2 = scansDisp1;
for ii = 1:length(dValues)
    scan = yOCTInterfToScanCpx(interfAtFocus, dim, ...
        'dispersionQuadraticTerm', dValues(ii), 'n', in.tissueRefractiveIndex);
    scansDisp1(:,:,ii) = mean(log(abs(scan)),3);

    scan = yOCTInterfToScanCpx(squeeze(interfs(:,:,1)), dim, ...
        'dispersionQuadraticTerm', dValues(ii), 'n', in.tissueRefractiveIndex);
    scansDisp2(:,:,ii) = mean(log(abs(scan)),3);
end

figure(212);
set(gcf, 'Units', 'pixels', 'Position', [100 100 1600 800]);
for ii = 1:length(dValues)
    subplot(2,length(dValues),ii)

    imagesc(squeeze(scansDisp1(:,:,ii)));
    colormap gray;
    ylim(focusPositionInImageZpix + [-80 80]);
    if dValues(ii) == dispersionQuadraticTerm
        title(sprintf('Estimated\nDispersion\n%.4g\\mum',dValues(ii)));
    else
        title(sprintf('%.4g',dValues(ii)));
    end

    % Turn off tick labels if not needed
    set(gca, 'XTickLabel', []);
    if ii ~= 1
        set(gca, 'YTickLabel', []);
    else
        ylabel('At Focus');
    end

    subplot(2,length(dValues),ii+length(dValues));
    imagesc(squeeze(scansDisp2(:,:,ii)));
    colormap gray;
    ylim(focusPositionInImageZpix + [-80 80]);
    % Turn off tick labels if not needed
    set(gca, 'XTickLabel', []);
    if ii ~= 1
        set(gca, 'YTickLabel', []);
    else
        ylabel('At First Position');
    end

end
saveas(gcf, [in.tempFolder 'dispersion.png']);

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

        normVal = sqrt(mean( (s(maxIdZEnv)).^2 ));
        errorFun = @(x)( ...
            sqrt(mean( (model(x)-s(maxIdZEnv)).^2 )) ... % RMS
            / normVal ... Normalized by function value
            );
        
        opts = optimset('TolX',0.01, 'MaxIter',5e4, 'MaxFunEvals',1e6);
        a = fminsearch(errorFun,x0, opts);
        
        pos(xI) = a(2);
        %plot(zI(maxIdZEnv),[s(maxIdZEnv) model(a)]);
    end
    %plot(pos);
end