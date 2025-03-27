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
photobleach_L_shape = true; % Select "true" if you want to photobleach an L shape outside of the square. Select "false" if not.
photobleach_crosshairs = false; % Select "true" if you want to photobleach a crosshair pattern through the center of the square. Select "false" if not.

% Photobleach configurations
exposure_mm_sec = 20; % mm/sec
nPasses = 1; % Keep as low as possible. If galvo gets stuck, increase number


%% Initialize empty arrays
x_start_mm = [];
y_start_mm = [];
x_end_mm   = [];
y_end_mm   = [];


%% Define patterns
% Square (Base)
square_x_start = [-1, +1, +1, -1]*scale/2 + bias;
square_y_start = [-1, -1, +1, +1]*scale/2 + bias;
square_x_end   = [+1, +1, -1, -1]*scale/2 + bias;
square_y_end   = [-1, +1, +1, -1]*scale/2 + bias;

% L-shape extension
L_x_start = [-1.2, -1.2]*scale/2 + bias;
L_y_start = [+1.2, +1.2]*scale/2 + bias;
L_x_end   = [-1.2, +0  ]*scale/2 + bias;
L_y_end   = [-1.2, +1.2]*scale/2 + bias;

% Crosshairs
cross_x_start = [0, 1]*scale/2 + bias;
cross_y_start = [1, 0]*scale/2 + bias;
cross_x_end   = [0, -1]*scale/2 + bias;
cross_y_end   = [-1, 0]*scale/2 + bias;


%% Combine patterns dynamically
if photobleach_L_shape
    x_start_mm = [x_start_mm, square_x_start, L_x_start];
    y_start_mm = [y_start_mm, square_y_start, L_y_start];
    x_end_mm   = [x_end_mm,   square_x_end,   L_x_end];
    y_end_mm   = [y_end_mm,   square_y_end,   L_y_end];
else
    x_start_mm = [x_start_mm, square_x_start];
    y_start_mm = [y_start_mm, square_y_start];
    x_end_mm   = [x_end_mm,   square_x_end];
    y_end_mm   = [y_end_mm,   square_y_end];
end

if photobleach_crosshairs
    x_start_mm = [x_start_mm, cross_x_start];
    y_start_mm = [y_start_mm, cross_y_start];
    x_end_mm   = [x_end_mm,   cross_x_end];
    y_end_mm   = [y_end_mm,   cross_y_end];
end


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