function dimensions = yOCTLoadInterfFromFile_ThorlabsHeader (inputDataFolder, octSystem, chirp)
%This function loads dimensions structure header
% INPUTS:
%   - inputDataFolder - OCT folder with header.xml file or srr files
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

%% Load XML
% Any fileDatastore request to AWS S3 is limited to 1000 files in 
% MATLAB 2021a. Due to this bug, we have replaced all calls to 
% fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
% 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
ds=imageDatastore(awsModifyPathForCompetability([inputDataFolder '/Header.xml']),'ReadFcn',@xml2struct,'FileExtensions','.xml');
xDoc = ds.read;
xDoc = xDoc.Ocity;

%% Figure out which of the Thorlabs systems are we using
if ~exist('octSystem','var') || isempty(octSystem)
    if ~isempty(regexp(xDoc.Instrument.Model.Text,'Ganymed','once'))
        octSystem = 'Ganymede';
    elseif ~isempty(regexp(xDoc.Instrument.Model.Text,'Telesto','once'))
        octSystem = 'Telesto';
    else
        error('Unknown OCT system');
    end
end

%% Process Xml
order = 1;

%Lambda Size
dimensions = yOCTLoadInterfFromFile_ThorlabsHeaderLambda(inputDataFolder,octSystem,chirp);
order = order + 1;

try
    %See if Data was aquired in 1D mode
    % Any fileDatastore request to AWS S3 is limited to 1000 files in 
    % MATLAB 2021a. Due to this bug, we have replaced all calls to 
    % fileDatastore with imageDatastore since the bug does not affect imageDatastore. 
    % 'https://www.mathworks.com/matlabcentral/answers/502559-filedatastore-request-to-aws-s3-limited-to-1000-files'
    ds=imageDatastore(awsModifyPathForCompetability([inputDataFolder '/data/SpectralFloat.data']),'ReadFcn',@fread,'FileExtensions','.data');
    oneDMode = true;
catch
    oneDMode = false;
end
if (oneDMode)
    %x,y, B Scan Averaging are all 1
    dimensions.x.order  = NaN;
    dimensions.x.values = 0;
    dimensions.x.units  = 'NaN';
    dimensions.x.index  = 1;
    dimensions.x.origin = 'Unknown';
    dimensions.y.order  = NaN;
    dimensions.y.values = 0;
    dimensions.y.units  = 'NaN';
    dimensions.y.index  = 1;
    dimensions.y.indexMax = 1;
    dimensions.y.origin = 'Unknown';
    dimensions.AScanAvg.order = 2;
    dataFile = xDoc.DataFiles.DataFile{4}; %This is the xml file specifing 'SpectralFloat.data' file
    AScanAvgN = str2double(dataFile.Attributes.RangeX);
    dimensions.AScanAvg.index = 1:AScanAvgN;
    dimensions.AScanAvg.index = dimensions.AScanAvg.index(:)';
    dimensions.AScanAvg.indexMax = AScanAvgN;
    return;
end

%2D or 3D Modes

%Along B Scan Axis (x)
sizeX = str2double(xDoc.Image.SizePixel.SizeX.Text);
sizeXReal = str2double(xDoc.Image.SizeReal.SizeX.Text)*1000;
dimensions.x.order = order;
dimensions.x.values = linspace(0,1,sizeX).*sizeXReal;
dimensions.x.values = dimensions.x.values(:)';
dimensions.x.units = 'microns';
dimensions.x.index = (1:sizeX);
dimensions.x.index = dimensions.x.index(:)';
dimensions.x.origin = 'Unknown';
order = order + 1;

%Across B Scan Axis (y)
if ~isfield(xDoc.Image.SizeReal,'SizeY') || str2double(xDoc.Image.SizeReal.SizeY.Text) == 0  %No Y axis
    sizeY = 1;
    dimensions.y.order = NaN;
    dimensions.y.values = 0;
    dimensions.y.units = 'microns';
    dimensions.y.index = 1;
    dimensions.y.indexMax = 1;
    dimensions.y.origin = 'Unknown';
else
    sizeY = str2double(xDoc.Image.SizePixel.SizeY.Text);
    sizeYReal=str2double(xDoc.Image.SizeReal.SizeY.Text)*1000;

    if (sizeYReal > 0)
        %Y Dimension exists
        dimensions.y.order = order;
        dimensions.y.values = linspace(0,1,sizeY).*sizeYReal;
        dimensions.y.values = dimensions.y.values(:)';
        dimensions.y.units = 'microns';
        dimensions.y.index = 1:sizeY;
        dimensions.y.index = dimensions.y.index(:)';
        dimensions.y.indexMax = sizeY;
        dimensions.y.origin = 'Unknown';
        order = order + 1;

    else
        %Y Dimension is actually BScanAvg
        BScanAvgN = sizeY;
        sizeY = 1;
        dimensions.y.order = NaN;
        dimensions.y.values = 0;
        dimensions.y.units = 'microns';
        dimensions.y.index = 1;
        dimensions.y.indexMax = sizeY;
        dimensions.y.origin = 'Unknown';
    end
end

%A Scan Averaging
AScanAvgN = str2double(xDoc.Acquisition.IntensityAveraging.AScans.Text);
if (AScanAvgN > 1)
    dimensions.AScanAvg.order = order;
    dimensions.AScanAvg.index = 1:AScanAvgN;
    dimensions.AScanAvg.index = dimensions.AScanAvg.index(:)';
    dimensions.AScanAvg.indexMax = AScanAvgN;

    order = order + 1;
end

%B Scan Averaging
if (exist('BScanAvgN','var'))
    %'Y' is actually the B-Scan Avg axis    
else
    BScanAvgN = 1;
    if isfield(xDoc.Acquisition,'SpeckleAveraging')
        BScanAvgN = str2double(xDoc.Acquisition.SpeckleAveraging.SlowAxis.Text);
    end
end
if (BScanAvgN > 1)
    dimensions.BScanAvg.order = order;
    dimensions.BScanAvg.index = 1:BScanAvgN;
    dimensions.BScanAvg.index = dimensions.BScanAvg.index(:)';
    dimensions.BScanAvg.indexMax = BScanAvgN;

    order = order + 1;
end

%% Determine dimensions for apodization

%Get Index of data file that has spectral information
spectralInd = 0;
for i = 1:length(xDoc.DataFiles.DataFile)
    if strcmp(xDoc.DataFiles.DataFile{i}.Text(1:13),'data\Spectral')
        spectralInd = i;
        break;
    end
end
if spectralInd == 0
    error('missing raw spectral data in folder')
end

%Extract apodization information from the relevant frame
dimensions.aux.interfSize = str2double(xDoc.DataFiles.DataFile{spectralInd}.Attributes.SizeX);
dimensions.aux.apodSize = str2double(xDoc.DataFiles.DataFile{spectralInd}.Attributes.ApoRegionEnd0);

%A Scan Binning if relevant
dimensions.aux.AScanBinning = str2double(xDoc.Acquisition.IntensityAveraging.Spectra.Text);

end
