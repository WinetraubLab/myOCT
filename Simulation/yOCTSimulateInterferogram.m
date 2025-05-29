function [interf, dim] = yOCTSimulateInterferogram(varargin)
% This function generates an interferogram that matches the 3D volume
% provided as input. Simulation parameters are provided below.
%
% INPUTS:
%   SAMPLE:
%       data: a 3D matrix (z,x,y) or a 2D matrix (z,x)
%       pixelSize_um: how many microns is each pixel in data 
%           (x,y,z directions). Default 1. Units: microns
%       n: medium refractive index. default: 1.33. Air has index 1
%   SCANNER PARAMETERS:
%       lambdaRange: Lambda range [min,max]. Default [800 1000]. Units: nm
%           See yOCTLoadInterfFromFile_ThorlabsHeaderLambda for Thorlab's
%           system values.
%       numberOfSpectralBands: how many bands in the range? Default 2048
%           bands. This is the Ganymede default. 
%       dispersionQuadraticTerm: See yOCTInterfToScanCpx for further
%           explanation about this term. Default is 0 (no dispersion).
%   PHYSICAL PROBE PARAMETERS:
%       referenceArmZOffset_um: When set to 0 (default) scanner's z=0 is
%           placed at data(1,:,:). If increasing referenceArmZOffset_um
%           then reference arm will be placed deeper data(i,:,:) removing
%           all information from higher values of data.
%       focusPositionInImageZpix: which pixel is at focus. set to 1 for the
%           top most pixel in the scan. Default is NaN which disables this.
%       focusSigma: focus width in pixels, default: 20.
%
% OUTPUTS:
%   intef: interferogram values.
%   dim: dimensions structure (see yOCTLoadInterfFromFile for more info).

%% Parse inputs
p = inputParser;
addRequired(p,'data');
addParameter(p,'pixelSize_um', 1);
addParameter(p,'n', 1.33);
addParameter(p,'lambdaRange', [800 1000]);
addParameter(p,'numberOfSpectralBands', 2048);
addParameter(p,'dispersionQuadraticTerm', 0);
addParameter(p,'referenceArmZOffset_um',0);
addParameter(p,'focusPositionInImageZpix',NaN);
addParameter(p,'focusSigma',20);

parse(p,varargin{:});
in = p.Results;
data = in.data;
n = in.n;
N = in.numberOfSpectralBands;

if(in.dispersionQuadraticTerm ~= 0)
    error('dispersionQuadraticTerm is not implemented yet');
end

%% Project data onto the scanner z coordinate system 
zScanner_um = yOCTInterfToScanCpx_getZ(in.lambdaRange(1), in.lambdaRange(2), N, n);

% Interpolate
dataInterp = zeros(length(zScanner_um), size(data,2), size(data,3));
zData_um = (0:(size(data,1)-1))*in.pixelSize_um;
for ix = 1:size(data,2)
    for iy = 1:size(data,3)
        % Extract the 1D slice along z
        slice = squeeze(data(:, ix, iy));
        
        % Interpolate to new zeta positions
        dataInterp(:, ix, iy) = interp1(...
            zData_um - in.referenceArmZOffset_um, ... Set refrence arm as default position.
            slice, zScanner_um, 'linear', 0); % Put 0 where no value provided
    end
end

%% Apply focusing attenuation
if ~isnan(in.focusPositionInImageZpix)
    for zI=1:size(dataInterp,1)
        factorZ = exp(-(zI-in.focusPositionInImageZpix).^2/(2*in.focusSigma)^2);
        dataInterp(zI,:,:) = dataInterp(zI,:,:)*factorZ;
    end
end

%% Compute interferogram
[interf, dim] = yOCTSimulateInterferogram_core(...
    dataInterp,'pixelSizeXY',in.pixelSize_um,'lambdaRange',in.lambdaRange);