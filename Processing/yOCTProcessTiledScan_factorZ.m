function factorZ = yOCTProcessTiledScan_factorZ( ...
  zI, focusPositionInImageZpix, focusSigma)
% This function computes the factor from z. Factor is 1 in focus
% INPUTS:
%   zI - depth for each pixel (pixel number)
%   focusPositionInImageZpix - focus position (pixel)
%   focusSigma - sigma (pixles)
% OUTPUT: factor for each zI position

factorZ = exp(-(zI-focusPositionInImageZpix).^2/(2*focusSigma)^2) + ...
    exp(-3^2/2); % Minimum floor to prevent NaN from low weights
