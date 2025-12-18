function [interferogram, apodization, prof, isFileValid] = yOCTLoadInterfFromFile_ThorlabsSRRData(varargin)
%Interface implementation of yOCTLoadInterfFromFile. See help yOCTLoadInterfFromFile
%Reads SRR files
% OUTPUTS:
%   - interferogram - interferogram data, apodization corrected. 
%       Dimensions order (lambda,x,y,AScanAvg,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - apodization - OCT baseline intensity, without the tissue scatterers.
%       Dimensions order (lambda,apodization #,y,BScanAvg). 
%       If dimension size is 1 it does not appear at the final matrix
%   - prof - profiling data - for debug purposes
%   - isFileValid - true if all files loaded successfully, false if any file was corrupted/missing 

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

apodSize =   dimensions.aux.apodend - dimensions.aux.apodstart + 1;

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
isFileValid = true; %Track if all files loaded successfully
for fi=1:length(fileIndex)
    td=tic;
    filePath = sprintf('%s/Data_Y%04d_YTotal%d_B%04d_BTotal%d_%s.srr',...
        inputDataFolder,...
        dimensions.y.index(yI(fi)),dimensions.y.indexMax,...
        dimensions.BScanAvg.index(BScanAvgI(fi)),dimensions.BScanAvg.indexMax,...
        strrep(dimensions.aux.OCTSystem,'_SRR','') ... Remove _SRR from system
        );
    filePath = awsModifyPathForCompetability(filePath);
 
    %Load Data
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    
    % Read file with validation: returns NaN array if corrupted/missing to allow processing to continue
    ds=imageDatastore(filePath,'ReadFcn',@(a)(DSRead(a,dimensions.aux.headerTotalBytes)),'FileExtensions','.srr');
    [temp, fileValid] = yOCTLoadInterfFromFile_ReadFile(...
        filePath, ...
        [N, dimensions.aux.scanend], ...
        @()(ds.read), ...
        'ThorlabsSRRData');
    
    if ~fileValid
        isFileValid = false;
    end
    
    prof.totalFrameLoadTimeSec = prof.totalFrameLoadTimeSec + toc(td);
    temp = reshape(temp,N,[]);

    %Read apodization
    apod = double(temp(:,dimensions.aux.apodstart:dimensions.aux.apodend,:));
    
    %Read interferogram
    interf = double(temp(:,dimensions.aux.scanstart:dimensions.aux.scanend,:)); 
    
    %Save
    apodization(:,:,fi) = apod;
    interferogram(:,:,yI(fi),:,BScanAvgI(fi)) = interf;
end

function temp = DSRead(fileName, headerTotalBytes) 

try
    fid = fopen(fileName);

    %Skip header
    fseek(fid, headerTotalBytes, 'cof'); 

    %Read
    data = fread(fid,'uint16');

    % data is 2 bytes (2^16) but really only ranges from 0-4096 (2^12)
    temp = uint16(rem(data, 4096));

    %Cleanup
    fclose(fid);
catch ME
    disp(['Error in DSRead sub-function while trying to read: ' fileName]);
    ME
    rethrow(ME)
end