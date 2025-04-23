function z_um = yOCTInterfToScanCpx_getZ( ...
    lambda_min_nm, lambda_max_nm, N, n)
% This is an auxilary function to yOCTInterfToScanCpx that is used to
% compute the z position of each pixel in the converted interferogram.
% Default values are from Thorlab's Ganaymede scanner, scanning in water.
%
% INPUTS:
%   lambda_min_um: interferogram minimum wavelength in nm. Default: 800nm
%   lambda_max_um: interferogram maximum wavelength in nm. Default: 1000nm
%   N: number of pixels in the interferogram. Default: 2048.
%   n: material index of refraction. Default: 1.33
% OUTPUTS:
%   z_um: depth, z= 0 is the position where reference arm and sample
%       arm are the same distance. z increases with depth. Units: microns

%% Input check
if ~exist('lambda_min_nm','var')
    lambda_min_nm=800;
end
if ~exist('lambda_max_nm','var')
    lambda_max_nm=1000;
end
if ~exist('N','var')
    N=2048;
end
if ~exist('n','var')
    n=1.33;
end

lambda_nm = sort([lambda_min_nm lambda_max_nm]);

%% Compute
% See equation 3.6 in link: https://www.ncbi.nlm.nih.gov/books/NBK554044/

lambda0_um = mean(lambda_nm)/1e3;
dlambda_um = diff(lambda_nm)/1e3;

zStepSizeAir = 1/2*lambda0_um^2/dlambda_um; %1/2 factor is because light goes back and forth
zStepSizeMedium = zStepSizeAir/n;
z_um = linspace(0,zStepSizeMedium*N/2,N/2); 
