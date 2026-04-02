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

%% Compute median depth profile aligned to tissue surface
[medianIntensity_dB, dimensionsCorrected] = ...
    computeAlignedMedianProfile(octData, dimensions);
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
function [medianIntensity_dB, dimensionsCorrected] = computeAlignedMedianProfile(oct, dimensions)
    % Compute the median depth profile after aligning each A-scan to the
    % tissue surface. For each corrected Z level, gathers the corresponding
    % values directly from the input volume using linear indexing and
    % computes the median across all (x,y) positions.

    pixZOffset = 5;

    %% Find surface position
    % Ensure dimensions in um for depth calculations
    dimensions = yOCTChangeDimensionsStructureUnits(dimensions, 'um');
    [surfacePosition_pix, ~, ~] = yOCTFindTissueSurface(oct, dimensions, ...
        'outputUnits', 'pix', 'isVisualize', false);
    surfacePosition_pix = permute(surfacePosition_pix, [2 1]); % Align with oct coordinates (x,y)

    %% Precompute surface offsets for valid (x,y) positions
    nZ = size(oct, 1);
    nX = size(oct, 2);
    nY = size(oct, 3);

    surfStart = round(surfacePosition_pix) - pixZOffset;
    validMask = ~isnan(surfStart) & surfStart >= 1;

    [xGrid, yGrid] = ndgrid(1:nX, 1:nY);
    xValid = xGrid(validMask);
    yValid = yGrid(validMask);
    surfStartValid = surfStart(validMask);

    %% Compute median for each corrected Z level
    medianIntensity_dB = NaN(nZ, 1);

    for zi = 1:nZ
        srcZ = surfStartValid + zi - 1;
        inBounds = srcZ >= 1 & srcZ <= nZ;

        if ~any(inBounds)
            continue;
        end

        linearIdx = sub2ind([nZ, nX, nY], ...
            srcZ(inBounds), xValid(inBounds), yValid(inBounds));
        medianIntensity_dB(zi) = median(oct(linearIdx), 'omitnan');
    end

    %% Generate corrected dimensions
    dimensionsCorrected = dimensions;
    dz = diff(dimensions.z.values(1:2));
    dimensionsCorrected.z.values = dz * ((1:nZ) - pixZOffset);
    dimensionsCorrected.z.index = 1:nZ;
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
