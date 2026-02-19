function [mu_s, noiseFloor_dB] = yOCTEstimateScatteringCoefMuS(octData, dimensions, varargin)
% This function estimates mu_s from OCT volume data. It performs surface detection,
% alignment, and exponential fitting of the provided octData and dimensions.
%
% INPUTS:
%   octData    - OCT volume dB scale (log scale) from yOCTProcessTiledScan
%   dimensions - [z, x, y] dimensions structure from yOCTProcessTiledScan
%
% OPTIONAL PARAMETERS:
%   'tempFolder' - Where to save figure if generated (default: './TmpMuS/')
%   'v'          - Show plots and print results (default: false)
%
% OUTPUTS:
%   mu_s          - Scattering Coef, mm^-1 (small = better)
%   noiseFloor_dB - The minimum signal in dB

%% Parse inputs
p = inputParser;
addRequired(p, 'octData', @(x) isnumeric(x) && ndims(x)==3);
addRequired(p, 'dimensions', @isstruct);
addParameter(p, 'tempFolder', './TmpMuS/', @ischar);
addParameter(p, 'v', false, @islogical);
parse(p, octData, dimensions, varargin{:});

v = p.Results.v;
tempFolder = p.Results.tempFolder;

%% Align OCT volume to tissue surface (z=0 at tissue surface)
[octCorrected, dimensionsCorrected] = ...
    alignOctToSurface(octData, dimensions);

%% Compute median depth profile across all a-scans
medianIntensity_dB = median(octCorrected, [2 3], 'omitnan');  % Median over (x,y)
medianIntensity_dB = medianIntensity_dB(:);  % Convert to column vector
tissueZDepth_um = dimensionsCorrected.z.values(:);  % Depth values

% Remove NaN values at end where aligned data ran out
hasValidData = ~isnan(medianIntensity_dB);
medianIntensity_dB = medianIntensity_dB(hasValidData);
tissueZDepth_um = tissueZDepth_um(hasValidData);

if isempty(medianIntensity_dB)
    error('No valid data points after alignment and averaging');
end

%% Fit exponential model: I(z) = A * exp(-2*mu_s*z) + c
[mu_s, noiseFloor_dB, modelFunc] = fitExponentialModel(medianIntensity_dB, tissueZDepth_um);

%% Display results and save plot if verbose
if v
    % Print resulting mu_s and noise floor
    fprintf('\n=== Scattering Coefficient Estimation (mu_s) ===\n');
    fprintf('Scattering Coef (mu_s): %.2f mm^-1\n', mu_s);
    fprintf('Noise floor: %.2f dB\n', noiseFloor_dB);
    
    % Plot exponential fit
    figure('Color', [1 1 1]);
    plot(tissueZDepth_um, medianIntensity_dB, 'LineWidth', 2);
    hold on;
    plot(tissueZDepth_um, modelFunc(tissueZDepth_um), 'r--', 'LineWidth', 2);
    grid on;
    legend('Median OCT Intensity, t=0', ...
        sprintf('Model: exp(-2\\mu_sz)+c, \\mu_s=%.2f[mm^{-1}]', mu_s), ...
        'Location', 'best');
    xlabel('Depth [\mum]');
    ylabel('OCT Log Intensity [dB]');
    
    % Save figure
    if ~exist(tempFolder, 'dir')
        mkdir(tempFolder);
    end
    saveas(gcf, fullfile(tempFolder, 'scattering_coefficient_mu_s.png'));
    fprintf('Figure saved to: %s\n', fullfile(tempFolder, 'scattering_coefficient_mu_s.png'));
end
end


%% Helper functions
function [octCorrected, dimensionsCorrected] = alignOctToSurface(oct, dimensions)
    % Align OCT volume so that z=0 corresponds to tissue surface
    % It copies data from surface to end for each a-scan

    %% Find surface position
    % Ensure dimensions in um for depth calculations
    dimensions = yOCTChangeDimensionsStructureUnits(dimensions, 'um');
    [surfacePosition_pix, ~, ~] = yOCTFindTissueSurface(oct, dimensions, ...
        'outputUnits', 'pix', 'isVisualize', false);
    surfacePosition_pix = permute(surfacePosition_pix, [2 1]); % Align with oct coordinates (x,y)

    %% Create output data structure
    octCorrected = zeros(size(oct)) * NaN;

    %% Loop over all x,y pixels to compute average intensity profile
    pixZOffset = 5;
    for xi=1:size(oct,2)
        for yi=1:size(oct,3)
            sp = surfacePosition_pix(xi,yi) - pixZOffset;
            if isnan(sp) || sp<=0
                continue; % Can't find surface
            end

            aScan = oct(:,xi,yi);
            aScan = aScan(:);
            inTissueIndexes = sp:length(aScan);

            octCorrected(1:length(inTissueIndexes),xi,yi) = ...
                aScan(inTissueIndexes);
        end
    end

    %% Generate dimensions
    dimensionsCorrected = dimensions;
    dimensionsCorrected.z.values = diff(dimensions.z.values(1:2)) * ...
        ((1:size(octCorrected,1))-pixZOffset);
    dimensionsCorrected.z.index = 1:length(dimensionsCorrected.z.values);

    % Plot original vs corrected (only use for debugging/verification)
    if false  % Set to true to visualize alignment
        figure(1)
        subplot(1,2,1)
        imagesc(dimensions.x.values,dimensions.z.values,squeeze(oct(:,:,end/2)));
        title('Orig')
        colormap gray
        subplot(1,2,2)
        imagesc(dimensionsCorrected.x.values,dimensionsCorrected.z.values,squeeze(octCorrected(:,:,end/2)));
        title('Corrected')
        colormap gray
    end
end

function [mu_s, noiseFloor, modelFunc] = fitExponentialModel(im, tissueZDepth_um)
    % Fit exponential model: I(z) = A * exp(-2*mu_s*z) + c

    % Ensure all inputs are double
    im = double(im);
    tissueZDepth_um = double(tissueZDepth_um);

    % Find peak
    [~, peak] = max(im);
    
    % Define model: I(z) = A * exp(-2*z/depth_constant) + c
    model = @(x)(mag2db(x(1)*exp(-2*tissueZDepth_um/x(2))+x(3)));
    
    % Initial guess: [amplitude, depth_constant_um, noise_floor]
    % depth_constant in um (100 um initial guess)
    fit0 = [db2mag(max(im)), 100/2, db2mag(min(im))];
    
    % Fit using fminsearch
    fit1 = fminsearch(@(x)(mean(...
        (model(x) - im).^2 .* ... Error between model and data
        ((1:length(im))' > peak) ... Omit data for z below peak
        , 'omitnan')), fit0);
    
    % Extract mu_s and noiseFloor from fitted parameters
    mu_s = (fit1(2)/1000)^-1; % Scattering Coef mm^-1
    noiseFloor = mag2db(fit1(3)); % Noise floor from fitted model
    
    % Return fitted model function for plotting
    modelFunc = @(d)(mag2db(fit1(1)*exp(-2*double(d)/fit1(2)) + fit1(3)));
end
