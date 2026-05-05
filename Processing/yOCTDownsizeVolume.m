function [] = yOCTDownsizeVolume(volumePath, outputPath, downsampleFactor)
% This function downsamples a tif volume by taking every Nth sample and
% saves the result to a new 8-bit tif with updated metadata.
%
% INPUTS:
%   volumePath      - tif file or tif stack folder path
%   outputPath      - tif file path to save output
%   downsampleFactor - scalar or 3-element vector [z x y] (default: 5)
%
% OUTPUTS:
%   none

if ~exist('downsampleFactor','var') || isempty(downsampleFactor)
    downsampleFactor = 5;
end

if ~(ischar(volumePath) || isstring(volumePath))
    error('volumePath must be a tif file or tif folder path.');
end

if ~(ischar(outputPath) || isstring(outputPath))
    error('outputPath must be a tif file or tif folder path.');
end

[~,~,ext] = fileparts(char(outputPath));
if isempty(ext)
    error('outputPath must be a tif file path (not a folder).');
end

downsizeFromTif(volumePath, outputPath, downsampleFactor);

end

function [] = downsizeFromTif(filepath, outputPath, downsampleFactor)
filepath = char(filepath);
outputPath = char(outputPath);

if isscalar(downsampleFactor)
    downsampleFactor = repmat(downsampleFactor, 1, 3);
end

if numel(downsampleFactor) ~= 3
    error('downsampleFactor must be scalar or a 3-element vector for tif data.');
end

if any(downsampleFactor < 1) || any(mod(downsampleFactor,1) ~= 0)
    error('downsampleFactor must contain positive integers.');
end

[~, metadata] = yOCTFromTif(filepath, 'isLoadMetadataOnly', true);

if isstruct(metadata) && isfield(metadata,'x') && isfield(metadata,'y') && isfield(metadata,'z')
    nx = length(metadata.x.index);
    ny = length(metadata.y.index);
    nz = length(metadata.z.index);

    xI = 1:downsampleFactor(2):nx;
    yI = 1:downsampleFactor(3):ny;
    zI = 1:downsampleFactor(1):nz;

    [volumeOut, ~, c] = yOCTFromTif(filepath, 'xI', xI, 'yI', yI, 'zI', zI);
    metadataOut = metadata;
    metadataOut.x.values = metadata.x.values(xI);
    metadataOut.x.index = 1:length(xI);
    metadataOut.y.values = metadata.y.values(yI);
    metadataOut.y.index = 1:length(yI);
    metadataOut.z.values = metadata.z.values(zI);
    metadataOut.z.index = 1:length(zI);
    yOCT2Tif(volumeOut, outputPath, 'metadata', metadataOut, 'clim', c, 'maxbit', 2^8-1);
else
    error('Missing metadata in tif header. Cannot update metadata for output.');
end

end

