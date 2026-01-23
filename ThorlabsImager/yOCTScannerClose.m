function yOCTScannerClose(v)
% Close OCT scanner based on system type (Ganymede or Gan632).
% Hardware library must be loaded via yOCTHardwareLibSetUp before calling this function.
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
[octSystemModule, octSystemName, skipHardware] = yOCTHardwareLibSetUp();

%% Close scanner based on system type
if ~skipHardware
    switch(octSystemName)
        case 'ganymede'
            % Ganymede: C# DLL
            % Only close if ThorlabsImagerNET is loaded (scanner is initialized) to prevent crashes
            if ~isempty(which('ThorlabsImagerNET.ThorlabsImager'))
                try
                    ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose();
                catch ME
                    if (v)
                        warning('Error closing scanner: %s', ME.message);
                    end
                end
            else
                if (v)
                    fprintf('%s Scanner already closed or not initialized\n', datestr(datetime));
                end
            end
            
        case 'gan632'
            % Gan632: Python SDK
            try
                octSystemModule.oct.yOCTScannerClose();
            catch ME
                if (v)
                    warning('Error closing scanner: %s', ME.message);
                end
            end
            
        otherwise
            error('Unknown OCT system: %s', octSystemName);
    end
else
    if (v)
        fprintf('%s Scanner close skipped (skipHardware = true)\n', datestr(datetime));
    end
end

% Mark scanner as closed
yOCTScannerStateSet(false);

%% Finish up
if (v)
    fprintf('%s Scanner Closed\n', datestr(datetime));
end
