function [surfacePosition_mm,x_mm,y_mm] = yOCTFindTissueSurface(varargin)
% This function processes OCT scan data to identify tissue surface from the
% OCT image.
% USAGE:
%   [surfacePosition_mm, x_mm, y_mm] = yOCTFindTissueSurface(logMeanAbs, dimensions, 'param', value, ...)
% INPUTS:
%   Required:
%       logMeanAbs, dimensions - data structures from yOCTProcessTiledScan.
%   Optional: 
%       'isVisualize'          Set to true to generate image heatmap visualization figure. Default is false.
%       'octProbeFOV_mm'       Physical FOV used (mm). If left empty (default), the code assumes 
%                              all scans come from only one tile along X. This fallback works but might 
%                              reduce surface detection accuracy for stitched volumes.
%       'constantThreshold'    User-supplied intensity threshold (overrides Otsu detection).
%                              Keep it empty [] (default) to auto-detect this value with Otsu method.
% OUTPUTS:
%   - surfacePosition_mm- 2D matrix. dimensions are (y,x). What
%       height is image surface. Height measured from “user specified
%       tissue interface”, higher value means deeper. See: 
%       https://docs.google.com/document/d/1aMgy00HvxrOlTXRINk-SvcvQSMU1VzT0U60hdChUVa0/
%       physical dimensions of surfacePosition_mm are always returned in millimeters.
%   - x_mm,y_mm are the x,y positions that corresponds to surfacePosition_mm(y,x)
%       Units are always returned in millimeters, regardless of input units.

%% Parse inputs

p = inputParser;
addRequired(p,'logMeanAbs');
addRequired(p,'dimensions');
addParameter(p,'isVisualize',false,@islogical);
addParameter(p,'octProbeFOV_mm',[]);
addParameter(p, 'constantThreshold', [], @(x) isnumeric(x) || isempty(x));

parse(p,varargin{:});
in = p.Results;

logMeanAbs = in.logMeanAbs;
dim = in.dimensions;
isVisualize = in.isVisualize;
constantThreshold = in.constantThreshold;

% Define Detection Parameters
base_confirmations_required = 12; % Initial consecutive pixels required to confirm surface
z_size_threshold = 1000;           % Threshold to determine the starting depth based on image height
low_z_start = 1;                  % Starting pixel for images with a small Z dimension
high_z_start = 300;               % Starting pixel for images with a large Z dimension
sigma = 1.5;                      % Deviation for the Gaussian kernel

[z_size, x_size, y_size] = size(logMeanAbs); % Retrieve total scan sizes

% Adjust the start depth based on z_size_threshold to avoid initial reflections in large images
if z_size > z_size_threshold  
    start_depth = high_z_start;
else
    start_depth = low_z_start;
end

% Validate provided dimensions
isValid = isstruct(dim) && ...
          isfield(dim,'z') && isfield(dim.z,'values') && ~isempty(dim.z.values) && ...
          isfield(dim,'x') && isfield(dim.x,'values') && ~isempty(dim.x.values) && ...
          isfield(dim,'y') && isfield(dim.y,'values') && ~isempty(dim.y.values);

if ~isValid
    error('yOCTFindTissueSurface:InvalidDimensions', ...
          ['Valid dim.x/y/z values (with units) are required to map tissue ' ...
           'surface depths to physical units.']);
end


%% Determine number of tiles stitched together

% Each stitched tile is its own OCT frame and may have a slightly different
% brightness/exposure profile. We call 'computeOtsuThreshold()' for every tile.
% Otsu's method is an automatic way to pick a cut-off that best separates 
% “background” pixels (air/noise) from “foreground” pixels (tissue) by 
% maximising the contrast between those two groups. Using Otsu tile‑by‑tile
% keeps the detection accurate even when tiles vary too much.

% Work out how many X-tiles were stitched in the scan so that, later on,
% we can apply an intensity threshold per-tile instead of one global value.

% Make sure output is always in 'mm'
dim = yOCTChangeDimensionsStructureUnits(dim, 'mm');

% Determine pixel size in mm
pixelSize_mm = [];                       % init
if isstruct(dim) && isfield(dim,'x') && isfield(dim.x,'values') ...
        && numel(dim.x.values) >= 2
    pixelSize_mm = abs(dim.x.values(2) - dim.x.values(1));  % mm per pixel
end

% Determine number of tiles along X dimension and width of each tile
octProbeFOV_mm = in.octProbeFOV_mm;  % expect it is passed in; may be []

if ~isempty(octProbeFOV_mm) && ~isempty(pixelSize_mm)
    tileWidth_px = round(octProbeFOV_mm / pixelSize_mm);   % width of one tile in px
    numTilesX    = max(1, floor(x_size / tileWidth_px));   % tiles along X
else
    tileWidth_px = x_size;   % fallback: whole X treated as one tile (might degrade detection)
    numTilesX    = 1;
    fprintf(['%s octProbeFOV_mm or pixelSize_mm not provided or could not be determined. ', ...
             'Assuming X_tiles = 1.\n', ...
             '      Surface detection will treat the full X-range as a single tile, ', ...
             'even if multiple tiles were stitched together.\n\n'], ...
             datestr(datetime));
end


%% Identify tissue surface

% Create a matrix to store the Surface Depth for each (x, y) coordinate
surface_depth = zeros(x_size, y_size);

% Main Loop - For each Y slice, analyze the data to find the surface
for yIdx = 1:y_size

    % Set intensity threshold to use in the surface detection
    if ~isempty(constantThreshold) % User provided fixed intensity threshold
        intensity_threshold = constantThreshold;
    else
        % Dynamic intensity threshold computation using otsu for each tile
        [intensity_threshold, dynamic_offset] = computeOtsuThreshold(logMeanAbs, start_depth, ...
            z_size, yIdx, x_size, numTilesX, tileWidth_px);
    end

    % Surface detection for each Y slice
    current_slice = logMeanAbs(:, :, yIdx); % Current Y slice to be used for surface detection
    % Local function to detect surface of current slide
    surface_depth_profile = detectSurfacePerYSlice(current_slice, start_depth, z_size, ...
        x_size, base_confirmations_required, intensity_threshold, dynamic_offset);
     % Store the detected surface depths
    surface_depth(:, yIdx) = surface_depth_profile;
end


%% Configure the Gaussian Kernel Smoothing & Dimensions

kernel_size = ceil(sigma * 3) * 2 + 1;  % Determine kernel size based on sigma
gaussian_kernel = fspecial('gaussian', [kernel_size, kernel_size], sigma);  % Create Gaussian kernel

% Preprocessing Before Smoothing
surface_depth(isnan(surface_depth)) = 0;  % Replace NaN values with zeros to prepare for smoothing
smoothed_surface_depth = conv2(surface_depth, gaussian_kernel, 'same');  % Apply Gaussian filter to smooth the surface depth map

% Normalize so zeros added for NaNs don't bring down the average
normalizing_kernel = conv2(surface_depth ~= 0, gaussian_kernel, 'same');  % Create a normalization matrix from non-zero entries
smoothed_surface_depth = smoothed_surface_depth ./ normalizing_kernel;  % Normalize to account for initial zeros used for NaNs
smoothed_surface_depth(normalizing_kernel == 0) = NaN;  % Restore NaN values where no original data existed
smoothed_surface_depth = round(smoothed_surface_depth);  % Round smoothed values to the nearest integer for uniform depth representation

% Convert Depth found from Pixels to Units in dim.z.units like microns or mm
surface_depth_pixels = smoothed_surface_depth.'; % Transpose for consistent global orientation system
surfacePosition_mm = NaN(size(surface_depth_pixels)); % Output matrix with NaNs

% Assign dimensions
x_mm = dim.x.values(:);
y_mm = dim.y.values(:);
z = dim.z.values(:);

% Map depth indices to actual depth measurements in surfacePosition_mm

for i = 1:numel(surfacePosition_mm)
    index = surface_depth_pixels(i);
    if ~isnan(index) && index >= 1 && index <= length(z)
        surfacePosition_mm(i) = z(index);
    end
end


%% Generate heatmap of the identified surface for user visualization

if isVisualize
    figure;
    imagesc(x_mm, y_mm, surfacePosition_mm);
    set(gca,'YDir','normal');
    xlabel(['X-axis (' dim.x.units ')']);
    ylabel(['Y-axis (' dim.y.units ')']);
    title(['Surface Position (' dim.z.units ') – view from top']);
    colormap(flipud(jet));
    colorbar;
end
end % Main function ends


%% Local functions used

% Function to identify intensity threshold in the provided slice
function [intensity_threshold, dynamic_offset] = computeOtsuThreshold(...
            logMeanAbs, ...
            start_depth, ...
            z_size, ...
            yIdx, ...
            x_size, ...
            numTilesX, ...
            tileWidth_px)

%   computeOtsuThreshold - Computes a dynamic (Otsu) threshold 
%                          across multiple tiles in the X-dimension.
%   Inputs:
%       logMeanAbs  - 3D volume or data array
%       start_depth - Index where we start looking in Z
%       z_size      - Last index in Z
%       yIdx        - Chosen Y slice or index
%       x_size      - Total size in X
%       numTilesX   - Number of tiles along X dimension
%       tileWidth_px- Width in pixels of each tile
%   Output:
%       intensity_threshold - The resulting identified intensity threshold

    roi_data = []; % Initialize our master region of interest array
    for tileIdx = 1:numTilesX
        % Compute the pixel span of the current tile
        tileStart = (tileIdx - 1) * tileWidth_px + 1;           % Start of the tile
        tileEnd   = min(tileStart + tileWidth_px - 1, x_size);  % End of the tile
        tileCenter = floor((tileStart + tileEnd) / 2);  % Center column of the tile
        
        % Scale by ±2% of the tile width or at least ±3 px for safety
        halfWidth = max(3, floor(0.02 * tileWidth_px));      
        leftCol  = max(1, tileCenter - halfWidth);       % Left around the center
        rightCol = min(x_size, tileCenter + halfWidth);  % Right around the center

        % Grab the slice from Z=start_depth, X=these columns, Y=yIdx
        tiled_slice = logMeanAbs(start_depth:z_size, leftCol:rightCol, yIdx);
        
        % Apply a median filter to suppress salt-and-pepper noise  
        tiled_slice = medfilt2(tiled_slice, [3, 3]);  

        % Gaussian blur for speckle noise as well
        tiled_slice = imgaussfilt(tiled_slice, 1);  

        % Flatten and remove NaNs
        tiled_slice = tiled_slice(~isnan(tiled_slice));
        
        % Append to our master ROI array
        roi_data = [roi_data; tiled_slice];
    end
    
    if ~isempty(roi_data)
        % Normalize ROI to [0,1] for Otsu
        minVal = min(roi_data);
        maxVal = max(roi_data);
        rangeVal = maxVal - minVal;
        if rangeVal > eps
            roi_data_norm = (roi_data - minVal) / rangeVal;
            % graythresh returns normalized threshold [0,1]
            otsuLevel = graythresh(roi_data_norm); 
            % Map back to original intensity range
            intensity_threshold = otsuLevel * rangeVal + minVal;
            dynamic_offset = max(0.1, min(2, 0.1 * rangeVal));  % 10 % offset used to confirm surface
        else
            intensity_threshold = minVal; % ROI is nearly constant
            dynamic_offset = minVal;
            warning('Threshold set to minVal (%.3f) due to nearly constant ROI.', minVal);
            warning('Surface identification may be inaccurate.');
        end
    else
        % No valid data in ROI, fallback to our master constant
        intensity_threshold = -10;
        dynamic_offset = -12;
        warning('Threshold set to -10 because ROI is empty (no valid data).');
        warning('Surface identification may be inaccurate.');
    end
end % computeOtsuThreshold ends

% Function to obtain surface depth in the given slice
function surface_depth_profile = detectSurfacePerYSlice( ...
           current_slice, ...
           start_depth, ...
           z_size, ...
           x_size, ...
           base_confirmations_required, ...
           intensity_threshold, ...
           dynamic_offset)

%   detectSurfacePerYSlice Finds the surface depth in a 2D OCT slice
%   surface_depth_profile = detectSurfacePerYSlice(current_slice, start_depth, z_size, x_size, ...
%                               base_confirmations_required, intensity_threshold)
%   returns a column vector "surface_depth_profile" of length x_size, where each element
%   is the detected surface index for that column.
%   current_slice: 2D array [Z x X]
%   start_depth:   index in Z from which to start scanning down
%   z_size:        total size in Z dimension
%   x_size:        total size in X dimension
%   base_confirmations_required: max consecutive confirmations needed
%   intensity_threshold: the intensity threshold for detecting the surface

    surface_depth_profile = NaN(x_size, 1);
    adjustable_decrease = 1; % 
    for xIdx = 1:x_size % Iterate over each X position within the slice
        found = false;  % Flag to track if surface is found
        
        % Option to decrease confirmations needed if surface is not found
        for confirmations_required = base_confirmations_required:-1:(base_confirmations_required-adjustable_decrease)
            if found
                break;  % Exit if surface already found
            end
            
            % Scan down from the start_depth to bottom
            for zIdx = start_depth:z_size
                if current_slice(zIdx, xIdx) >= intensity_threshold % Check if pixel intensity is above threshold

                    % Confirm the surface with consecutive pixels above (intensity_threshold - 2)
                    if (zIdx + confirmations_required <= z_size) ...
                            && all(current_slice(zIdx+1:zIdx+confirmations_required, xIdx) > (intensity_threshold - dynamic_offset))
                        surface_depth_profile(xIdx) = zIdx; % Record the surface depth
                        found = true;
                        break; 
                    end
                end
            end
        end
    end
end % detectSurfacePerYSlice ends
