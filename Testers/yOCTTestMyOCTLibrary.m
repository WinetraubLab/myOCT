%This is the master tester, runs all!
%Designed to be run using runme_Jenkins

%% Pre test configuration
%Where to find files to be tested
mainTestVectorFolder1 = '\\171.65.17.174\s3\Users\Jenkins\';
mainTestVectorFolder2 = 's3://delazerdamatlab/Users/Jenkins/'; %S3 version

%Get main OCT folder
currentFileFolder = fileparts(mfilename('fullpath'));
yOCTMainFolder = [currentFileFolder '\..\'];

%% Low level test
yOCTTestLowLevel();

%% Test Reconstruction
disp('Reconstruction Tests... (Local Folder Version)');
yOCTTestReconstruction([mainTestVectorFolder1 'SampleOCTVolumes\'],true);
disp('Reconstruction Tests... (S3 Version)');
yOCTTestReconstruction([mainTestVectorFolder2 'SmallSampleOCTVolumes/'],true);

%% Test that Demos are working
disp('Demo Tests');
d = dir([yOCTMainFolder 'Demo*']);
for i=1:length(d)
    [~,functionName] = fileparts(d(i).name);
    disp(functionName);
    eval(functionName);
    close all;
end

%% Test Unzip
disp('Unzip Tests... (Local Folder Version)');
yOCTTestUnzip([mainTestVectorFolder1 'ZippedOCTFolder\']);
disp('Unzip Tests... (S3 Version)');
yOCTTestUnzip([mainTestVectorFolder2 'ZippedOCTFolder/']);

%% Test batch processing
disp('Testing Batch Processing... (S3 Version)');
myOCTBatchProcess([mainTestVectorFolder2 'SmallSampleOCTVolumes/'],{'parallelOption',1,'isSaveDicom','True'});
myOCTBatchProcess([mainTestVectorFolder2 'SmallSampleOCTVolumes/'],{'parallelOption',2,'isSaveDicom','True'});

%% Test Load and save Tif files
yOCTTestLoadSaveTif;

%% Test tiled scan reconstruction
yOCTTestReconstruction([mainTestVectorFolder2 'TiledScans/TiledXYZ/']);

%% Test reslicing
yOCTTestReslice;

%% Test geometric transformations
disp('Geometric Transformation Tests');
yOCTTestGeometricTransform;

%% Done!
disp('All Tests Completed');