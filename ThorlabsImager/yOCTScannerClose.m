function yOCTScannerClose(v)
% Close OCT scanner based on system type (Ganymede or Gan632).
% Hardware library must be loaded via yOCTLoadHardwareLib before calling this function.
%
% INPUTS:
%   v: verbose mode, default: false

%% Input checks
if ~exist('v','var')
    v = false;
end

%% Start closing
if (v)
    fprintf('%s Closing Scanner...\n', datestr(datetime));
end

% Load library (should already be loaded to memory)
[octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLib();

%% Close scanner based on system type
if ~skipHardware
    switch(octSystemName)
        case 'ganymede'
            % Ganymede: C# DLL
            ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose();
            
        case 'gan632'
            % Gan632: Python SDK
            octSystemModule.oct.yOCTScannerClose();
            
        otherwise
            error('Unknown OCT system: %s', octSystemName);
    end
else
    if (v)
        fprintf('%s Scanner close skipped (skipHardware = true)\n', datestr(datetime));
    end
end

%% Finish up
if (v)
    fprintf('%s Scanner Closed\n', datestr(datetime));
end
