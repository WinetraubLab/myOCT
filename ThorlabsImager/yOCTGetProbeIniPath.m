function p = yOCTGetProbeIniPath(magnification, scanHead, variant)
% Returns the absolute path to a probe .ini calibration file.
%
% INPUTS:
%   magnification - (required) Objective lens magnification.
%       Options: '10x', '20x', '40x'
%
%   scanHead - (required) OCT scan head system identifier.
%       Options: 'OCTG' (Current Gan632 system setup) or 'OCTP900' (Current Ganymede system setup)
%
%   variant - (optional, default '') Additional calibration variant.
%       Used when the same magnification + scanHead combination has
%       multiple calibrations (for example 40x SUMMER/WINTER configurations).
%       Options: 'WINTER', 'SUMMER', or '' (when only one exists)
%
% EXAMPLES:
%   p = yOCTGetProbeIniPath('10x', 'OCTG');
%   p = yOCTGetProbeIniPath('10x', 'OCTP900');
%   p = yOCTGetProbeIniPath('20x', 'OCTP900');
%   p = yOCTGetProbeIniPath('40x', 'OCTP900', 'SUMMER');
%   p = yOCTGetProbeIniPath('40x', 'OCTG', 'WINTER');
%
% FILE NAMING CONVENTION:
%   Probe Olympus - {magnification} - {scanHead} - {variant}.ini
%   Examples:
%     Probe Olympus - 10x - OCTG.ini
%     Probe Olympus - 40x - OCTG - WINTER.ini

%% Input checks
if ~exist('magnification','var') || isempty(magnification)
    error('magnification is required. Options: ''10x'', ''20x'', ''40x''');
end
if ~exist('scanHead','var') || isempty(scanHead)
    error('scanHead is required. Options: ''OCTG'', ''OCTP900''');
end
if ~exist('variant','var') || isempty(variant)
    variant = '';
end

%% Build probe file name
if isempty(variant)
    probeName = sprintf('Probe Olympus - %s - %s.ini', magnification, upper(scanHead));
else
    probeName = sprintf('Probe Olympus - %s - %s - %s.ini', magnification, upper(scanHead), upper(variant));
end

%% Build path and verify file exists
currentFileFolder = [fileparts(mfilename('fullpath')) '\'];
p = awsModifyPathForCompetability([currentFileFolder '\' probeName]);

if ~exist(p, 'file')
    % List available probe files to help the user
    probeFiles = dir(fullfile(fileparts(mfilename('fullpath')), 'Probe Olympus - *.ini'));
    availableProbes = strjoin({probeFiles.name}, '\n  ');
    error('Probe file not found: %s\nAvailable probes:\n  %s', probeName, availableProbes);
end
