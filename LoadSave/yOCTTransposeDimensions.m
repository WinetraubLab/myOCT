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
%   'outputPath' - if specified, saves directly to file/folder and returns empty data.
%       Can be a .tif file or folder path (same as yOCT2Tif).
%       If not specified, returns transposed data in memory.
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
p = inputParser;
addRequired(p, 'arg1'); % data or inputPath
addOptional(p, 'arg2', []); % metadata or newOrder
addOptional(p, 'arg3', []); % clim (only if arg1 is data)
addOptional(p, 'arg4', []); % newOrder (only if arg1 is data)
addParameter(p, 'outputPath', '');

parse(p, varargin{:});
in = p.Results;

%% Determine input mode
if isnumeric(in.arg1)
    % Mode 1: Pre-loaded data
    data = in.arg1;
    metadata = in.arg2;
    clim = in.arg3;
    newOrder = in.arg4;
    
    if isempty(metadata) || isempty(newOrder)
        error('When providing data directly, must provide: data, metadata, clim, newOrder');
    end
    
elseif ischar(in.arg1) || isstring(in.arg1)
    % Mode 2: File path
    inputPath = char(in.arg1);
    newOrder = in.arg2;
    
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
    
    if ~isempty(in.outputPath)
        yOCT2Tif(dataOut, in.outputPath, 'clim', climOut, 'metadata', metadataOut);
        dataOut = []; % Clear to save memory
    end
    return;
end

%% Transpose the data
dataOut = permute(data, permuteOrder);

%% Update metadata
% Original metadata has fields for x, y, z
% After permutation, these need to be swapped to match new dimension order

% Create position to dimension name mapping for output
% Output position 1 has dimension newOrder(1), etc.
outputPosToDimName = struct();
outputPosToDimName.pos1 = lower(newOrder(1)); % Position 1 (rows in output)
outputPosToDimName.pos2 = lower(newOrder(2)); % Position 2 (cols in output) 
outputPosToDimName.pos3 = lower(newOrder(3)); % Position 3 (pages in output)

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
    if isfield(metadata, sourceDimName)
        metadataOut.(standardName) = metadata.(sourceDimName);
        metadataOut.(standardName).order = outPos; % Update order field
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
metadataOut.transposeInfo.timestamp = datestr(now);

%% Color limits unchanged
climOut = clim;

%% Save or return
if ~isempty(in.outputPath)
    yOCT2Tif(dataOut, in.outputPath, 'clim', climOut, 'metadata', metadataOut);
    dataOut = []; % Clear to save memory
    fprintf('Transposed volume saved to: %s\n', in.outputPath);
end

end
