% Run this demo to use Thorlabs system to photobleach a pattern of a square
% with an L shape on its side

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))

%% Inputs

% When set to true the stage will not move and we will not
% photobleach. Use "true" when you would like to see the output without
% physcaily running the test.
skipHardware = false;

% Photobleach pattern configuration
octProbePath = yOCTGetProbeIniPath('40x','OCTP900'); % Select lens magnification

% Pattern to photobleach. System will photobleach n lines from 
% (x_start(i), y_start(i)) to (x_end(i), y_end(i))
scale = 0.25; % Length of each side of the square in mm
bias = 0.0; % Use small bias [mm] to make sure lines are not too close to the edge of FOV
x_start_mm = [-1, +1, +1, -1]*scale/2+bias;
y_start_mm = [-1, -1, +1, +1]*scale/2+bias;
x_end_mm   = [+1, +1, -1, -1]*scale/2+bias;
y_end_mm   = [-1, +1, +1, -1]*scale/2+bias;

% Photobleach configurations
exposure_mm_sec = 20; % mm/sec
nPasses = 1; % Keep as low as possible. If galvo gets stuck, increase number

%% Photobleach
yOCTPhotobleachTile(...
    [x_start_mm; y_start_mm],...
    [x_end_mm; y_end_mm],...
    'octProbePath',octProbePath,...
    'exposure',exposure_mm_sec,...
    'nPasses',nPasses,...
    'skipHardware',skipHardware, ...
    'plotPattern',true, ...
    'v',true); 