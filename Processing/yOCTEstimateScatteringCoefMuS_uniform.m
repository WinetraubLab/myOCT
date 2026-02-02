function [mu_s, noiseFloor] = yOCTEstimateScatteringCoefMuS_uniform(im,depth_um,isPlot)
% This function estimates mu_s given aligned OCT data. Asuming uniform
% distribution
% INPUTS:
%   im: Aligned OCT data (must be after surface detection), average over x,y
%       im must be in dB (log scale).
%   depth_um: depth
%   isPlot: set to true to plot
% OUTPUTS:
%   mu_s: scattering coef, mm^-1 (small = better)
%   noiseFloor - the minimum singal

%% Input checks
if ~exist('isPlot','var')
    isPlot = true;
end

if length(im) ~= length(depth_um)
    error('length of im should be the same as depth_um');
end
depth_um = depth_um(:);
im = im(:);

%% Model
% Define Model

[~,peak] = max(im);
model = @(x)(mag2db(x(1)*exp(-2*depth_um/x(2))+x(3)));
fit0 = [db2mag(max(im)), 100/2, db2mag(min(im))];
fit1 = fminsearch(@(x)(mean(...
    (model(x)-im).^2 .* ... Error between model and data
    ((1:length(im)) > peak)' ... Omit data for z below peak
    ,'omitnan')),fit0);

noiseFloor = mag2db(fit1(3));
mu_s = (fit1(2)/1000)^-1; % Scattering Coef mm^-1

if isPlot
    figure('Color',[1 1 1]);
    plot(depth_um,im,depth_um,model(fit1));
    grid on;
    legend('Mean OCT Intensity, t=0',sprintf('Model: exp(-2\\mu_sz)+c, \\mu_s=%.1f[mm^{-1}]',mu_s));
    xlabel('Depth [\mum]');
    ylabel('OCT Log Intensity [dB]');
end
