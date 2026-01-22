function dimensions = yOCTLoadInterfFromFile_ThorlabsSRRHeader (inputDataFolder,octSystem,chirp)
%In case this is a thorlabs file that is saved in srr format.
%Make sure SRR Name convention is 'Data_Y%04d_Total%d_B%04d_Total%d_%s.srr
%Specifing (by order)
%   - Y0001 = Y scan number
%   - Total5 = Total number of Y scans
%   - B0001 = B scan number (B scan average)
%   - Total1 = Total number of B scan averages
%   - %s = OCT System+
% Optional inputs, if they are unknown, we will figure them out
%   OCTSystem if we know it (otherwise set to '')
%   chirp - if we have it (otherwise set to [])

if (awsIsAWSPath(inputDataFolder))
    %Load Data from AWS
    isAWS = true;
    awsSetCredentials;
    inputDataFolder = awsModifyPathForCompetability(inputDataFolder);
else
    isAWS = false;
end

if ~exist('chirp','var')
    chirp = [];
end

%% Load SRR File 
% Any fileDatastore request to AWS S3 is limited to 1000 files in 
% MATLAB 2021a. Due to this bug, we have replaced all calls to 
% fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
% 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
ds=imageDatastore(inputDataFolder,'ReadFcn',@readSRRHeader,'fileExtensions','.srr');
[headerFile,info] = ds.read; %Read first file

%% Parse File Name 
[~,fName] = fileparts(info.Filename);
t = textscan(fName,'Data_Y%04d_YTotal%d_B%04d_BTotal%d_%s');

if (isempty(t{2}) || isempty(t{4}) || isempty(t{end}) || isempty(t{end}{:}))
    %Filename formating is wrong
    error(sprintf(['SRR file formating is wrong.\n' ...
        'This code expects this file name format: %s.srr\n'] ...
        ,'Data_Y%04d_YTotal%d_B%04d_BTotal%d_%s')); %#ok<SPERR>
end

sizeY = t{2};
BScanAvgN = t{4};
OCTSystem1 = t{end}{:};

if ~exist('octSystem','var') || isempty(octSystem)
    octSystem = OCTSystem1; %We had no idea what was the OCT system, now we do
end

%% Lambda
order = 1;

%Lambda Size
dimensions = yOCTLoadInterfFromFile_ThorlabsHeaderLambda(inputDataFolder,octSystem,chirp);
order = order + 1;

if length(dimensions.lambda.values) ~= headerFile.size1
    error('Size of lambda in chirp does not match data on SRR file');
end

%% All Other Dimensions

sizeX=(headerFile.scanend-headerFile.scanstart);
if sizeX ~= round(sizeX)
    error('B scan file size is wired');
end
dimensions.x.order = order;
dimensions.x.values = linspace(0,1,sizeX);
dimensions.x.values = dimensions.x.values(:)';
dimensions.x.units = 'NA';
dimensions.x.index = (1:sizeX);
dimensions.x.index = dimensions.x.index(:)';
dimensions.x.origin = 'Unknown';
order = order + 1;

%% Add the other direction (Y)
dimensions.y.order = order;
dimensions.y.values = linspace(0,1,sizeY);
dimensions.y.values = dimensions.y.values(:)';
dimensions.y.units = 'NA';
dimensions.y.index = (1:sizeY);
dimensions.y.index = dimensions.y.index(:)';
dimensions.y.indexMax = sizeY;
dimensions.y.origin = 'Unknown';
order = order + 1;

%% Add B Scan Average+
dimensions.BScanAvg.order = order;
dimensions.BScanAvg.index = (1:BScanAvgN);
dimensions.BScanAvg.index = dimensions.BScanAvg.index(:)';
dimensions.BScanAvg.indexMax = BScanAvgN;
order = order + 1;

%% Auxilery parameters
dimensions.aux.headerTotalBytes = headerFile.headerTotalBytes;
dimensions.aux.scanstart = headerFile.scanstart+1;
dimensions.aux.scanend = headerFile.scanend;
dimensions.aux.apodstart = headerFile.apodstart+1;
dimensions.aux.apodend = headerFile.apodend;
dimensions.aux.OCTSystem = OCTSystem;

end

function header = readSRRHeader(fName)
    fid = fopen(fName);
    tline = fgetl(fid);
    headerSizeBytes = sscanf(tline,'headersize=%d');

    %Read Header
    headerLines = fread(fid,headerSizeBytes,'*char')';
    headerLines = split(headerLines);
    
    %Total bytes in header
    header.headerTotalBytes = ftell(fid);
    fclose(fid);

    %Parse Header
    for i=1:length(headerLines)
        headerL = headerLines{i};
        if (isempty(headerL))
            continue;
        end
        tmp = split(headerL,'=');
        varName = tmp{1};
        varValue = tmp{2};

        switch(varName)
            case 'scanregions'
                p = split(varValue,',');
                header.scanstart  = str2double(p{2});
                header.scanend    = str2double(p{3});
            case 'aporegions'
                p = split(varValue,',');
                header.apodstart = str2double(p{2});
                header.apodend = str2double(p{3});
            otherwise
                eval(['header.' headerL  ';']);
        end
    end
end

