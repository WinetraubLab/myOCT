function yOCTScannerInit(octProbePath, v)
% Initialize OCT scanner with probe
%
% INPUTS:
%   octProbePath: path to probe
%   v: verbose mode, default: false

%% Input checks
if ~exist('v','var')
    v = false;
end

%% Start Initialization
if (v)
    fprintf('%s Initialzing Hardware...\n\t(if Matlab is taking more than 2 minutes to finish this step, restart hardware and try again)\n',datestr(datetime));
end

% Load library (should already be loaded to memory)
[octSystemModule, octSystemName, skipHardware] = yOCTHardwareLibSetUp();

%% Initialize scanner
if ~skipHardware
    % Close any existing scanner first (in case of previous error/incomplete run)
    try
        yOCTScannerClose(v);
    catch
        % Ignore errors if scanner wasn't initialized
    end
    
    % Initialize scanner based on system type
    switch(octSystemName)
        case 'ganymede'
            % Ganymede: Use C# DLL (ThorlabsImagerNET)
            ThorlabsImagerNET.ThorlabsImager.yOCTScannerInit(octProbePath);
    
        case 'gan632'
            % GAN632: Use Python SDK (pyspectralradar)
            octSystemModule.oct.yOCTScannerInit(octProbePath);
    
        otherwise
            error('This should never happen')
    end
end

%% Finish up
if (v)
    fprintf('%s Initialzing Hardware Completed\n',datestr(datetime));
end
