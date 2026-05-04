function volumeOut = yOCTDownsizeVolume(volumePath, downsampleFactor)
% This function downsamples a tif volume by taking every Nth sample.
%
% USAGE:
%   volumeOut = yOCTDownsizeVolume(volumePath, downsampleFactor)
%
% INPUTS:
%   volumePath - tif file or tif stack folder path
%   downsampleFactor - scalar or vector with one factor per dimension
%       default is 5

if ~exist('downsampleFactor','var') || isempty(downsampleFactor)
    downsampleFactor = 5;
end

if ~(ischar(volumePath) || isstring(volumePath))
    error('volumePath must be a tif file or tif folder path.');
end

volumeOut = downsizeFromTif(volumePath, downsampleFactor);

end

function volumeOut = downsizeFromTif(filepath, downsampleFactor)
filepath = char(filepath);

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

    volumeOut = yOCTFromTif(filepath, 'xI', xI, 'yI', yI, 'zI', zI);
else
    data = yOCTFromTif(filepath);
    volumeOut = downsizeNumericVolume(data, downsampleFactor);
end

end

function volumeOut = downsizeNumericVolume(volumeIn, downsampleFactor)
if isscalar(downsampleFactor)
    downsampleFactor = repmat(downsampleFactor, 1, ndims(volumeIn));
end

if numel(downsampleFactor) ~= ndims(volumeIn)
    error('downsampleFactor must be scalar or match number of dimensions.');
end

if any(downsampleFactor < 1) || any(mod(downsampleFactor,1) ~= 0)
    error('downsampleFactor must contain positive integers.');
end

idx = cell(1, ndims(volumeIn));
for d = 1:ndims(volumeIn)
    idx{d} = 1:downsampleFactor(d):size(volumeIn, d);
end

volumeOut = volumeIn(idx{:});

