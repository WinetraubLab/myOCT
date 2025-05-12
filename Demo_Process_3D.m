% Run this demo to load and process 3D OCT Images in a batch format due to
% memory limitations. This script does not process TildScan see
% Demo_3DTildScan.m
yOCTSetLibraryPath(); % Set path

%% Iputs
%Wasatch
filePath = ['.\'];
dispersionQuadraticTerm = -1.514e08; %Use Demo_DispersionCorrection to find the term

yFramesPerBatch = 1; %How many Y frames to load in a single batch, optimzie this parameter to save computational time

%% Process
tic;
[meanAbs,speckleVariance,dimensions] = yOCTProcessScan(filePath, ...
    {'meanAbs','speckleVariance'}, ... Which functions would you like to process. Option exist for function hendel
    'dispersionQuadraticTerm', dispersionQuadraticTerm, ...
    'nYPerIteration', yFramesPerBatch, ...
    'showStats',true, ...
    'interpMethod', 'sinc5');
toc;

%% Save To File
tic;
yOCT2Tif(log(meanAbs),'tmp.tif'); %Save to File
yOCT2Dicom(log(meanAbs),'tmp.dcm',dimensions); %Save to File
%meanAbs2 = yOCTFromTif('tmp.tif'); %Load From File
toc;

%% Visualization - example
%Preform max projection along z
figure(1);
scanAbsMxProj = squeeze(max(meanAbs,[],dimensions.lambda.order));
imagesc(dimensions.x.values, dimensions.y.values, scanAbsMxProj');
xlabel(['x direction [' dimensions.x.units ']']);
ylabel(['y direction [' dimensions.y.units ']']);
title('Max Projection');

%Present one of the B-Scans
figure(2);
imagesc(log(squeeze(meanAbs(:,:,round(end/2)))));
title('Middle B-Scan');
xlabel('x direction');
ylabel('z direction');