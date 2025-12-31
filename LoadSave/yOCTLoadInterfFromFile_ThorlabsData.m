function [interferogram, apodization, prof, isFileValid] = yOCTLoadInterfFromFile_ThorlabsData(varargin)
%Interface implementation of yOCTLoadInterfFromFile. See help yOCTLoadInterfFromFile
% OUTPUTS:
%   - interferogram - interferogram data, apodization corrected. 
%       Dimensions order (lambda,x,y,AScanAvg,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - apodization - OCT baseline intensity, without the tissue scatterers.
%       Dimensions order (lambda,apodization #,y,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - prof - profiling data - for debug purposes
%   - isFileValid - true if file loaded successfully, false if it was corrupted/missing 

%% Input Checks
if (iscell(varargin{1}))
    %the first varible contains a cell with the rest of the varibles, open it
    varargin = varargin{1};
end 

inputDataFolder = varargin{1};
if (awsIsAWSPath(inputDataFolder))
    %Load Data from AWS
    awsSetCredentials;
    inputDataFolder = awsModifyPathForCompetability(inputDataFolder);
end

%Optional Parameters
for i=2:2:length(varargin)
    switch(lower(varargin{i}))
        case 'dimensions'
            dimensions = varargin{i+1};
        otherwise
            %error('Unknown parameter');
    end
end

%% Determine dimensions
[sizeLambda, sizeX, sizeY, AScanAvgN, BScanAvgN] = yOCTLoadInterfFromFile_DataSizing(dimensions);   

if (sizeX == 1)
    %% 1D Mode, Different loading scheme
    
    prof.numberOfFramesLoaded = 1;
    
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    spectralFilePath = awsModifyPathForCompetability([inputDataFolder '/data/SpectralFloat.data']);
    
    % ReadFile creates datastore internally and handles all validation
    [temp, isFileValid, prof.totalFrameLoadTimeSec] = yOCTLoadInterfFromFile_ReadFile(...
        spectralFilePath, ...
        sizeLambda * AScanAvgN, ...
        @(a)(double(DSRead(a,'float32'))), ...
        '.data', ...
        'ThorlabsData');
    
    temp = reshape(temp,[sizeLambda,AScanAvgN]);
    interferogram = zeros(sizeLambda,sizeX,sizeY, AScanAvgN, BScanAvgN);
    interferogram(:,1,1,:,1) = temp;
    apodization = NaN; %No Apodization in file
    return;
end

interfSize = dimensions.aux.interfSize;
apodSize = dimensions.aux.apodSize;
AScanBinning = dimensions.aux.AScanBinning;

%% Generate File Grid
%What frames to load
[yI,BScanAvgI] = meshgrid(1:sizeY,1:BScanAvgN);
yI = yI(:)';
BScanAvgI = BScanAvgI(:)';

%fileIndex is organized such as beam scans B scan avg, then moves to the
%next y position
if (isfield(dimensions,'BScanAvg'))
    fileIndex = (dimensions.y.index(yI)-1)*dimensions.BScanAvg.indexMax + dimensions.BScanAvg.index(BScanAvgI)-1;
else
    fileIndex = (dimensions.y.index(yI)-1);
end

%% Loop over all frames and extract data
%Define output structure
interferogram = zeros(sizeLambda,sizeX,sizeY, AScanAvgN, BScanAvgN);
apodization   = zeros(sizeLambda,apodSize,sizeY,1,BScanAvgN);
N = sizeLambda;
prof.numberOfFramesLoaded = length(fileIndex);
prof.totalFrameLoadTimeSec = 0;
isFileValid = true;
for fi=1:length(fileIndex)
    spectralFilePath = awsModifyPathForCompetability([inputDataFolder '/data/Spectral' num2str(fileIndex(fi)) '.data']);
 
    %Load Data
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    
    % ReadFile creates datastore internally and handles validations
    [temp, currentFileIsValid, frameLoadTime_sec] = yOCTLoadInterfFromFile_ReadFile(...
        spectralFilePath, ...
        N * interfSize, ...
        @(a)(double(DSRead(a,'short'))), ...
        '.data', ...
        'ThorlabsData');
    
    % Track overall validity: false if ANY file is invalid
    isFileValid = isFileValid & currentFileIsValid;
    
    prof.totalFrameLoadTimeSec = prof.totalFrameLoadTimeSec + frameLoadTime_sec;
    temp = reshape(temp,[N,interfSize]);

    %Read apodization
    apod = temp(:,1:apodSize);
    
    %Read interferogram
    interf = temp(:,apodSize+1:end); 
    
    %Average over AScanBinning
    if (AScanBinning > 1)
        avgFilt = ones(1,AScanBinning)/(AScanBinning);
        interfAvg = filter2(avgFilt,interf);
        interfAvg = interfAvg(:,max(1,floor((AScanBinning)/2)):AScanBinning:end);    
    else
        interfAvg = interf;
    end
    
    %Save
    apodization(:,:,fi) = apod;
    if (AScanAvgN > 1)
        %Reshape to extract A scan averaging
        tmpR = reshape(interfAvg,...
                [sizeLambda,AScanAvgN,sizeX]);
        interferogram(:,:,yI(fi),:,BScanAvgI(fi)) = permute(tmpR,[1 3 2]);
    else
        interferogram(:,:,yI(fi),:,BScanAvgI(fi)) = interfAvg;
    end
end

function temp = DSRead(fileName, dataType) %dataType can be 'short','float32'
fid = fopen(fileName);
temp = fread(fid,inf,dataType);
fclose(fid);
