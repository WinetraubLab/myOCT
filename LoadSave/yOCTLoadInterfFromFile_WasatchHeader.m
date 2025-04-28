function [dimensions] = yOCTLoadInterfFromFile_WasatchHeader(inputDataFolder)
%This function loads dimensions structure from xml header
% INPUTS:
%   - inputDataFolder - OCT folder with header.xml file

%% Figure Out basic Parameters
if (awsIsAWSPath(inputDataFolder))
    %Load Data from AWS
    awsSetCredentials;
    inputDataFolder = awsModifyPathForCompetability(inputDataFolder);
end

%% Header Information
%Determine if this is a 2D or 3D Volume
try
    %Quarry how many files are there tif (Tif files represent a 2D Mode
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    ds=imageDatastore([inputDataFolder 'raw_0*.tif'],'ReadFcn',@(a)DSInfo_Tif(a));
    nFiles = length(ds.Files);
    
    %Read info from first file
    out = ds.read();
    
    %Get Dimensions
    sizeX = out.sizeX;
    sizeLambda = out.sizeLambda;
    BScanAvgN = nFiles;
    sizeY = 1;
    
    %Set reader functions
    rawFilePath = @(i)(sprintf('%sraw_%05d.tif',inputDataFolder,i));
    
    is2D = true;
catch
    %No Tif Files exist, this is a 3D Mode
    
    %Get file names
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    ds=imageDatastore([inputDataFolder '*_raw_us_*.bin'],'ReadFcn',@(a)DSInfo_Bin(a),'FileExtensions','.bin');
    nFiles = length(ds.Files);
    
    %Read info from first file
    out = ds.read();
    
    %Get Dimensions
    sizeX = out.sizeX;
    sizeLambda = out.sizeLambda;
    BScanAvgN = out.bScanAvgFrameNumber;
    sizeY = nFiles/BScanAvgN;
    
    %Set reader functions
    rawFilePath = @(i)(sprintf('%s%05d_raw_us_%d_%d_%d.bin',inputDataFolder,i,sizeLambda,sizeX,BScanAvgN));    
    
    is2D = false;
end

%% Figure out lambda

%Information from Wasatch
%variables->lmbd(nm)=cl0+cl1*pixel+cl2*pixel^2+cl3*pixel^3
cl0=6.57328E+02;
cl1=8.28908E-02;
cl2=-1.10175E-06;
cl3=-7.04714E-11;

pixel = 1:(sizeLambda);
lambda = cl0+cl1*pixel+cl2*pixel.^2+cl3*pixel.^3;

%% Build Dimensions Structure
order = 1;

%Lambda Size
dimensions.lambda.order  = order;
dimensions.lambda.values = lambda;
dimensions.lambda.values = dimensions.lambda.values(:)';
dimensions.lambda.units = 'nm [in air]';
order = order + 1;

%Along B Scan Axis (x)
dimensions.x.order = order;
dimensions.x.values = linspace(0,1,sizeX);
dimensions.x.values = dimensions.x.values(:)';
dimensions.x.units = 'NA';
dimensions.x.index = (1:sizeX);
dimensions.x.index = dimensions.x.index(:)';
dimensions.x.origin = 'Unknown';
order = order + 1;

if (sizeY > 1)
    %Across B Scan Axis (y)
    dimensions.y.order = order;
    dimensions.y.values = linspace(0,1,sizeY);
    dimensions.y.values = dimensions.y.values(:)';
    dimensions.y.units = 'NA';
    dimensions.y.index = (1:sizeY);
    dimensions.y.index = dimensions.y.index(:)';
    dimensions.y.indexMax = sizeY;
    dimensions.y.origin = 'Unknown';
    order = order + 1;

else
    dimensions.y.order = NaN;
    dimensions.y.values = 0;
    dimensions.y.units = 'microns';
    dimensions.y.index = 1;
    dimensions.y.indexMax = 1;
    dimensions.y.origin = 'Unknown';
end

if (BScanAvgN>1)
    %Across B Scan Axis (y)
    dimensions.BScanAvg.order = order;
    dimensions.BScanAvg.index = 1:BScanAvgN;
    dimensions.BScanAvg.index = dimensions.BScanAvg.index(:)';
    dimensions.BScanAvg.indexMax = BScanAvgN;
    
    order = order + 1;
end

%% Auximarly Data
dimensions.aux.is2D = is2D;
dimensions.aux.rawFilePath = rawFilePath;

function out = DSInfo_Tif(fileName)
temp = imfinfo(fileName,'tif');
out.sizeX = temp.Height; %Number of A scans in a B Scan
out.sizeLambda = temp.Width; %Number of pixels in an A-scan

function out = DSInfo_Bin(fileName)
%Process file name
[~, fn, ~] = fileparts(fileName);
temp = sscanf(fn,'%05d_raw_us_%d_%d_%d');
out.sizeX = temp(3); %Number of A scans in a B Scan
out.sizeLambda = temp(2); %Number of pixels in an A-scan
out.scanNumber = temp(1);
out.bScanAvgFrameNumber = temp(4);