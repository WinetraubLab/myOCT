function [interf, dim] = yOCTSimulateInterferogram_core(varargin)
% This function generates an interferogram that matches the 3D volume 
% provided as input. data dimension z is assume to match k-space, but is
% not explicitly given. In fact, it may change depending on the medium.
% Use yOCTInterfToScanCpx_getZ to get z depth corresponding to data z dim.
%
% INPUTS:
%   data - a 3D matrix (z,x,y) or a 2D matrix (z,x)
%   pixelSizeXY - how many microns is each pixel, default 1. Units: microns
%   lambdaRange - Lambda range [min,max]. Default [800 1000]. Units: nm
% OUTPUTS:
%   intef - interferogram values
%   dim - dimensions structure (see yOCTLoadInterfFromFile for more info)

%% Parse inputs
p = inputParser;
addRequired(p,'data');

addParameter(p,'pixelSizeXY',1);
addParameter(p,'lambdaRange',[800 1000])

parse(p,varargin{:});
in = p.Results;
data = in.data;

%% Pad data to increase k space by factor of 2
data(end:(2*end),:,:) = 0;

%% K space (wave number in 1/nm)

% Bounds from bandwidth
kMax = lambda2k(min(in.lambdaRange));
kMin = lambda2k(max(in.lambdaRange));

k=linspace(kMin,kMax,size(data,1));

%% Generate dimension structure
dim.lambda.order = 1;
dim.lambda.values = k2lambda(k);
dim.lambda.units = 'nm [in air]';
dim.x.order = 2;
dim.x.values = (0:(size(data,2)-1))*in.pixelSizeXY;
dim.x.units = 'microns';
dim.x.index = 1:length(dim.x.values);
dim.x.origin = 'Unknown';
if (size(data,3)==1)
    % No Y-axis
    dim.y.order = 3;
    dim.y.values = 0;
    dim.y.units = 'microns';
    dim.y.index = 1;
    dim.y.origin = 'Unknown';
else
    dim.y.order = 3;
    dim.y.values = (0:(size(data,3)-1))*in.pixelSizeXY;
    dim.y.units = 'microns';
    dim.y.index = 1:length(dim.y.values);
    dim.y.origin = 'Unknown';
end

%% Interferogram
interf = real(fft(data,[],1));

% Normalize to match energy in data (doubling data size requires doubling
% the energy)
interf = interf*2;

end
function k=lambda2k(lambda)
k = 2*pi./(lambda);
end
function lambda=k2lambda(k)
lambda = 2*pi./(k);
end