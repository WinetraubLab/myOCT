function [dataOut, metadataOut, climOut] = yOCTTransposeDimensions(varargin)
% This function transposes/reslices a 3D OCT volume by reordering its dimensions
% while preserving yOCT metadata structure. Unlike yOCTReslice which does geometric
% interpolation, this performs simple array transposition - no interpolation.
%
% USAGE:
%   [dataOut, metadataOut, climOut] = yOCTTransposeDimensions(data, metadata, clim, newOrder)
%   [dataOut, metadataOut, climOut] = yOCTTransposeDimensions(inputPath, newOrder)
%   yOCTTransposeDimensions(inputPath, newOrder, 'outputPath', outputPath)
%
% INPUTS:
%   Option 1 - Pre-loaded data:
%       data - 3D array with dimensions (Z, X, Y) as output by yOCTFromTif
%       metadata - metadata structure from yOCTFromTif with .x, .y, .z fields
%       clim - color limits [min max] from yOCTFromTif
%       newOrder - string specifying desired dimension order, e.g. 'YZX', 'XYZ'
%   
%   Option 2 - File path:
%       inputPath - path to TIFF file or folder (same as yOCTFromTif)
%       newOrder - string specifying desired dimension order, e.g. 'YZX', 'XYZ'
%
% PARAMETERS:
%   'outputPath' - if specified, saves directly to file and returns empty data.
%       Can be a .tif file or folder path (same as yOCT2Tif).
%       If not specified, returns transposed data in memory.
%
% NOTE: For 'XYZ' ordering, applies Fiji-compatible transformations (horizontal
%       flip, 90° rotation, Z-axis flip) to match ImageJ/Fiji "Reslice from Bottom".
%
% OUTPUTS:
%   dataOut - transposed 3D array (empty if outputPath specified)
%   metadataOut - updated metadata structure with swapped dimension fields
%   climOut - color limits (unchanged from input)
%
% DIMENSION ORDER:
%   Input data from yOCTFromTif is always (Z, X, Y)
%   newOrder string specifies how to rearrange: 'ZXY' = no change, 'YZX' = swap to (Y,Z,X), etc.
%   
% EXAMPLES:
%   % Load, transpose from (Z,X,Y) to (Y,Z,X), and return in memory
%   [data, meta, clim] = yOCTFromTif('input.tif');
%   [dataOut, metaOut, climOut] = yOCTTransposeDimensions(data, meta, clim, 'YZX');
%
%   % Load from file, transpose, and save directly
%   yOCTTransposeDimensions('input.tif', 'YZX', 'outputPath', 'output.tif');
%
%   % Transpose to make X the first dimension (useful for certain visualizations)
%   yOCTTransposeDimensions('data.tif', 'XYZ', 'outputPath', 'resliced.tif');

%% Input parsing
% Parse manually to avoid inputParser's ambiguity when mixing
% optional positional arguments with name-value parameter pairs.
outputPath = '';

% Extract trailing name-value pairs
args = varargin;
i = 1;
while i <= length(args)
    if (ischar(args{i}) || isstring(args{i})) && i < length(args)
        key = char(args{i});
        if strcmpi(key, 'outputPath')
            outputPath = char(args{i+1});
            args(i:i+1) = [];
            continue;
        end
    end
    i = i + 1;
end

%% Determine input mode
if isnumeric(args{1})
    % Mode 1: Pre-loaded data: (data, metadata, clim, newOrder)
    data = args{1};
    metadata = args{2};
    clim = args{3};
    newOrder = args{4};
    
    if isempty(metadata) || isempty(newOrder)
        error('When providing data directly, must provide: data, metadata, clim, newOrder');
    end
    
elseif ischar(args{1}) || isstring(args{1})
    % Mode 2: File path: (inputPath, newOrder)
    inputPath = char(args{1});
    newOrder = args{2};
    
    if isempty(newOrder)
        error('Must specify newOrder when providing file path');
    end
    
    % Load data
    [data, metadata, clim] = yOCTFromTif(inputPath);
    
else
    error('First argument must be either numeric data or file path string');
end

%% Validate newOrder
newOrder = upper(char(newOrder));
if length(newOrder) ~= 3 || ~all(ismember(newOrder, 'XYZ')) || ...
   length(unique(newOrder)) ~= 3
    error('newOrder must contain exactly one each of X, Y, Z (e.g., ''YZX'', ''XYZ'')');
end

%% Create dimension mapping
% Input dimensions are always (Z, X, Y) from yOCTFromTif
% Position 1 = Z, Position 2 = X, Position 3 = Y
inputOrder = 'ZXY';

% Map each dimension letter to its position in original data
dimNameToInputPos = struct('Z', 1, 'X', 2, 'Y', 3);

% Create permutation vector
% permuteOrder(i) tells which input dimension goes to output position i
permuteOrder = zeros(1, 3);
for i = 1:3
    dimName = newOrder(i);
    permuteOrder(i) = dimNameToInputPos.(dimName);
end

% Check if transpose is needed
if strcmp(newOrder, inputOrder)
    % No change needed
    dataOut = data;
    metadataOut = metadata;
    climOut = clim;
    
    if ~isempty(outputPath)
        yOCT2Tif(dataOut, outputPath, 'clim', climOut, 'metadata', metadataOut);
        dataOut = []; % Clear to save memory
    end
    return;
end

%% Transpose the data
dataOut = permute(data, permuteOrder);

% Apply Fiji "Reslice from Bottom" orientation for XYZ ordering
% This matches ImageJ/Fiji's reslice output convention
if strcmp(newOrder, 'XYZ')
    % 1. Flip horizontally (left-right)
    dataOut = flip(dataOut, 2);
    
    % 2. Rotate 90° counterclockwise (aligns axes to Fiji convention)
    % Note: rot90 changes dimensions, so we need to preallocate
    [sz1, sz2, sz3] = size(dataOut);
    dataRotated = zeros(sz2, sz1, sz3, class(dataOut)); % After rotation: rows↔cols swap
    for i = 1:sz3
        dataRotated(:,:,i) = rot90(dataOut(:,:,i), 1);
    end
    dataOut = dataRotated;
    
    % 3. Flip Z-axis (Fiji's "from Bottom" = max Z to min Z)
    dataOut = flip(dataOut, 3);
end

%% Update metadata
% Original metadata has fields for x, y, z
% After permutation, these need to be swapped to match new dimension order

% Create position to dimension name mapping for output
% Output position 1 has dimension newOrder(1), etc.
outputPosToDimName = struct();
outputPosToDimName.pos1 = lower(newOrder(1)); % Position 1 (rows in output)
outputPosToDimName.pos2 = lower(newOrder(2)); % Position 2 (cols in output) 
outputPosToDimName.pos3 = lower(newOrder(3)); % Position 3 (pages in output)

% IMPORTANT: For XYZ mode with Fiji transforms, rot90 swaps dimensions 1 and 2!
% So we need to swap the metadata assignments for positions 1 and 2
if strcmp(newOrder, 'XYZ')
    temp = outputPosToDimName.pos1;
    outputPosToDimName.pos1 = outputPosToDimName.pos2;
    outputPosToDimName.pos2 = temp;
end

% Create new metadata by reassigning dimension fields
metadataOut = struct();

% The output dimension order maps as:
% Output position 1 (1st array dim) should have metadata from dimension newOrder(1)
% Output position 2 (2nd array dim) should have metadata from dimension newOrder(2)
% Output position 3 (3rd array dim) should have metadata from dimension newOrder(3)

% Map output positions to standard names (z, x, y)
% In yOCT convention: position 1=z, position 2=x, position 3=y
standardNames = {'z', 'x', 'y'};

for outPos = 1:3
    standardName = standardNames{outPos};
    sourceDimName = outputPosToDimName.(['pos' num2str(outPos)]);
    
    % Copy metadata from source dimension to target dimension
    % This copies all fields: .values, .index, .units, .origin, .indexMax, etc.
    if isfield(metadata, sourceDimName)
        metadataOut.(standardName) = metadata.(sourceDimName);
        metadataOut.(standardName).order = outPos;
        
        % Update origin string to reflect transformation
        if isfield(metadataOut.(standardName), 'origin')
            originalOrigin = metadataOut.(standardName).origin;
            metadataOut.(standardName).origin = sprintf(...
                'Transformed from original %s dimension (%s -> array position %d). Original: %s', ...
                upper(sourceDimName), newOrder, outPos, originalOrigin);
        end
        
        % Flip coordinate values and index for XYZ ordering (Fiji transformations)
        if strcmp(newOrder, 'XYZ')
            % After rotation and flips, x and y coordinates are reversed
            if (strcmp(standardName, 'x') || strcmp(standardName, 'y'))
                if isfield(metadataOut.(standardName), 'values')
                    metadataOut.(standardName).values = flip(metadataOut.(standardName).values);
                end
                if isfield(metadataOut.(standardName), 'index')
                    metadataOut.(standardName).index = flip(metadataOut.(standardName).index);
                end
            end
        end
    end
end

% Copy any additional metadata fields (not x, y, z)
allFields = fieldnames(metadata);
for i = 1:length(allFields)
    fieldName = allFields{i};
    if ~ismember(fieldName, {'x', 'y', 'z'})
        metadataOut.(fieldName) = metadata.(fieldName);
    end
end

% Add provenance information
metadataOut.transposeInfo.originalOrder = inputOrder;
metadataOut.transposeInfo.newOrder = newOrder;
metadataOut.transposeInfo.permuteVector = permuteOrder;
if strcmp(newOrder, 'XYZ')
    metadataOut.transposeInfo.fijiTransforms = 'flip(dim2) -> rot90 -> flip(dim3)';
end
metadataOut.transposeInfo.timestamp = datestr(now);

% Add transformation notes and warnings
if ~isfield(metadataOut, 'notes')
    metadataOut.notes = {};
end
metadataOut.notes{end+1} = sprintf('Volume transposed from %s to %s order on %s', ...
    inputOrder, newOrder, datestr(now));
    
if strcmp(newOrder, 'XYZ')
    metadataOut.notes{end+1} = 'Applied Fiji-compatible geometric transformations (horizontal flip + 90° rotation + Z flip).';
    metadataOut.notes{end+1} = 'WARNING: Coordinate values may not be geometrically accurate due to 90-degree rotation.';
    metadataOut.notes{end+1} = 'For geometric accuracy, refer to transposeInfo and original dimension metadata.';
end

metadataOut.notes{end+1} = 'Dimension ordering in yOCT: position 1=z field, position 2=x field, position 3=y field (always).';
metadataOut.notes{end+1} = 'Physical dimension meaning: check .origin field of each dimension for semantic information.';

%% Color limits unchanged
climOut = clim;

%% Save or return
if ~isempty(outputPath)
    yOCT2Tif(dataOut, outputPath, 'clim', climOut, 'metadata', metadataOut);
    dataOut = []; % Clear to save memory
    fprintf('Transposed volume saved to: %s\n', outputPath);
end

end
