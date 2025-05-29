function Demo_Spectral
%This demo demonstrates how to extract a single band from an inmage (spectral OCT)
%this demo is for 2D but can be extanded for 3D

yOCTSetLibraryPath(); % Set path

%% Iputs
%Ganymede
filePath = ['\\171.65.17.174\MATLAB_Share\Jenkins\myOCT Build\TestVectors\' ...
    'Ganymede_2D_BScanAvg\'];

global dispersionQuadraticTerm
dispersionQuadraticTerm = 100; %Use Demo_DispersionCorrection to find the term

global interfe
global dimensionse
global apodization
global bandCenter
global bandWidth
%% Process
tic;

%Load Intef From file
[interf,dimensions,apodization] = yOCTLoadInterfFromFile(filePath ...
    ,'BScanAvgFramesToProcess', 1, ... To save time, load first few BScans. Comment out this line to load all BScans
    'YFramesToProcess',1 ... To save time, load only one plane.
    );

%Equispace interferogram to save computation time while re-processing
[interfe,dimensionse] = yOCTEquispaceInterf(interf,dimensions);

bandCenter = 1/2*sum(dimensionse.lambda.values([1 end]));
bandWidth = 1/2*abs(diff(dimensionse.lambda.values([end 1])));

figure(1);
visualization (); %Visualize the bandpassed signal

%% GUI Handeling
txt1 = uicontrol('Style','text',...
        'Position',[100 80 400 20],...
        'String','Window Center [nm]');
sld1 = uicontrol('Style', 'slider',...
        'Min',dimensionse.lambda.values(1),'Max',dimensionse.lambda.values(end),'Value',bandCenter,...
        'Position', [100 60 400 20],...
        'Callback', @SliderCallbackBandCenter); 
txt2 = uicontrol('Style','text',...
        'Position',[100 40 400 20],...
        'String','Window Width [nm]');
sld2 = uicontrol('Style', 'slider',...
        'Min',0,'Max',abs(diff(dimensionse.lambda.values([end 1]))),'Value',bandWidth,...
        'Position', [100 20 400 20],...
        'Callback', @SliderCallbackBandWidth); 

function visualization()
global interfe
global dimensionse
global apodization
global bandCenter
global bandWidth
global dispersionQuadraticTerm

%% Compute and present interferogram
scanCpx = yOCTInterfToScanCpx(interfe,dimensionse ...
    ,'dispersionQuadraticTerm', dispersionQuadraticTerm ...
    ,'band',bandCenter+bandWidth/2*[-1 1]);

subplot(4,1,2:4);
imagesc(log(mean(abs(scanCpx),3)));
caxis([-5 6]);
colormap gray;

%% Compute and present band
subplot(4,1,1);
lambda = dimensionse.lambda.values;
interfMean = mean(apodization,2);
interfMean = interfMean/max(interfMean);

hannStart = find(lambda>bandCenter-bandWidth/2,1,'first');
hannEnd =   find(lambda<bandCenter+bandWidth/2,1,'last');
filter = zeros(size(lambda));
filter(hannStart:hannEnd) = hann(length(hannStart:hannEnd));
plot(lambda,interfMean,lambda,filter);
grid on;
xlabel('Wavelength[nm]');
legend('Data','Band Pass');
title('Band');


%% GUI Callbacks
function SliderCallbackBandCenter (source,event)
global bandCenter;
bandCenter = source.Value;
visualization();

function SliderCallbackBandWidth (source,event)
global bandWidth;
bandWidth = source.Value;
visualization();
