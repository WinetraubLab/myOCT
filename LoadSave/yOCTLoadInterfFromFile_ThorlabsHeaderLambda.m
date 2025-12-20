function dimensions = yOCTLoadInterfFromFile_ThorlabsHeaderLambda(inputDataFolder,OCTSystem,chirp)
%This script figures out what is lambda of the data folder
% Optional inputs, if they are unknown, we will figure them out
%   chirp - if we have it (otherwise set to [])

%% Figure out basic Parameters

%To get lambda min & max we contacted thorlabs
switch(OCTSystem)
    case {'Ganymede','Ganymede_SRR'}
        chirpFileName = 'ChirpGanymede.dat';
        lambdaMin = 796.23;%[nm] Manufacturer number: 824.16, See 2019-08-31GanymedeFilterCalibration Report for more details
        lambdaMax = 1010.02;%[nm]Manufacturer number: 1038.03, See 2019-08-31GanymedeFilterCalibration Report for more details
    case 'Gan632'
        chirpFileName = 'ChirpGanymede.dat';
        lambdaMin = 796; %[nm] TODO these will need to be measured, see 2019-08-31GanymedeFilterCalibration Report for more details
        lambdaMax = 1010; %[nm] TODO these will need to be measured, see 2019-08-31GanymedeFilterCalibration Report for more details
    case {'Telesto','Telesto_SRR'}
        chirpFileName = 'ChirpTelesto.dat';
        lambdaMin = 1208.69;%[nm] Manufacturer number: 1200.56, See 2018-12-04 Filter Calibration Report for more details
        lambdaMax = 1372.50;%[nm] Manufacturer number: 1367.75, See 2018-12-04 Filter Calibration Report for more details
    
    otherwise
        error('Unknown OCT System, please specify as input ''OCTSystem''')
end

%% Load Chirp File
if ~exist('chirp','var') || isempty(chirp)
    try
        chirp = yOCTLoadInterfFromFile_ThorlabsLoadChirp(inputDataFolder);
    catch ME
        %Couldn't load chirp file, try loading a local file instead
        warning(['Could not find chirp file in OCT folder, loading local file instead. Message: ' ME.message]);
        currentFileFolder = [fileparts(mfilename('fullpath')) '/'];
        
        chirp = yOCTLoadInterfFromFile_ThorlabsLoadChirp([currentFileFolder chirpFileName]);
    end
end

%% Compute and save lambda

%We belive that chirp describes the corrections for k. meaning
%k(i) = chirp(i)*A+B. Since lambda = 2*pi/k = 2*pi/(chirp*A+B) then
lambda = 1./( ...
            chirp .* ( 1/(length(chirp)-1)*(1/lambdaMax-1/lambdaMin) )+... chirp*A/2pi
            1/lambdaMin ... B/2pi
        );

dimensions.lambda.order  = 1;
dimensions.lambda.values = lambda;
dimensions.lambda.values = dimensions.lambda.values(:)';
dimensions.lambda.units = 'nm [in air]';
end