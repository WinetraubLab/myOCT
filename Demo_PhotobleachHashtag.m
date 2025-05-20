% Run this demo to use Thorlabs system to photobleach a pattern of a square
% with an L shape on its side

% Before running this script, make sure myOCT folder is in path for example
% by running: addpath(genpath('F:\Jenkins\Scan OCTHist Dev\workspace\'))
yOCTSetLibraryPath(); % Set path

%% Inputs

% When set to true the stage will not move and we will not
% photobleach. Use "true" when you would like to see the output without
% physcaily running the test.
skipHardware = true;

% Photobleach pattern configuration
octProbePath = yOCTGetProbeIniPath('40x'); % Select lens magnification

% Define the pattern 
base = 100e-3; %base seperation [mm]
lineLength = 6; %[mm]
vLineBias = 700e-3; % [mm]
hLineBias = -400e-3; % [mm]
vLinePositions = [-4  0 1 3]; %Unitless, vLine positions as multiplication of base
hLinePositions = [-3 -2 1 3]; %Unitless, hLine positions as multiplication of base

% Define lines from pattern - v
x_start_mm = vLinePositions*base+vLineBias;
x_end_mm   = vLinePositions*base+vLineBias;
y_start_mm = -lineLength/2*ones(size(vLinePositions));
y_end_mm   = +lineLength/2*ones(size(vLinePositions));

% Define lines from pattern - h
x_start_mm = [x_start_mm -lineLength/2*ones(size(hLinePositions))];
x_end_mm   = [x_end_mm   +lineLength/2*ones(size(hLinePositions))];
y_start_mm = [y_start_mm  hLinePositions*base+hLineBias];
y_end_mm   = [y_end_mm    hLinePositions*base+hLineBias];

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
axis xy
