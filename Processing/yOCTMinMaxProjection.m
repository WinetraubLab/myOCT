function octVolumeOut = yOCTMinMaxProjection(octVolume, mm, nSlices, axisNumber)
% This function performs min projection along a specific axis
% INPUTS:
%   octVolume - 3D OCT volume (z,x,y)
%   mm - can be 'min' (default) for min projection or 'max' for max
%       projection
%   nSlices - how many slices to perform min projection on (default: 5)
%   axisNumber - set to 1 (default) for z, 2 for x, 3 for y

%% Input checks 

if ~exist('mm','var')
    mm='min';
end

if ~exist('nSlices','var')
    nSlices = 5;
end
if ~exist('axisNumber','var')
    axisNumber = 1;
end

%% Rearrange the data such that the first axis is the axis to execute on
if axisNumber == 2
    octVolume = permute(octVolume, [2, 1, 3]); % (x,z,y)
elseif axisNumber == 3
    octVolume = permute(octVolume,[3, 1, 2]); % (y,z,x)
end

%% Loop over all volumes and compute min projection
octVolumeOut = zeros(size(octVolume), class(octVolume));
for i=1:size(octVolumeOut,1)
    % Pick the slice, make sure not to exceed 
    minI = max(round(i-nSlices/2),1);
    maxI = min(round(i+nSlices/2),size(octVolumeOut,1));

    % Min projection
    slice = octVolume(minI:maxI,:,:);
    if(strcmpi(mm,'min'))
        slice = min(slice,[],1);
    else
        slice = max(slice,[],1);
    end

    octVolumeOut(i,:,:) = slice;

end

%% Rearrange the data to the output form
if axisNumber == 2
    octVolumeOut = permute(octVolumeOut, [2, 1, 3]); % (x,z,y) --> (z,x,y)
elseif axisNumber == 3
    octVolumeOut = permute(octVolumeOut,[2, 3, 1]);  % (y,z,x) --> (z,x,y)
end

