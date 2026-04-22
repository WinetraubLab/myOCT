function yOCTHardware_closeScanner(octSystemModule, octSystemName, skipHardware, v)
% Helper function for yOCTHardware.
% Close OCT scanner based on system type (Ganymede or Gan632).
% Receives system state directly to avoid calling yOCTHardware('status') during teardown,
% which would fail if the scanner was never fully initialized.
%
% INPUTS:
%   octSystemModule - module handle (from gOCTHardwareStatus.module)
%   octSystemName   - system name string (from gOCTHardwareStatus.name)
%   skipHardware    - logical (from gOCTHardwareStatus.skipHardware)
%   v               - verbose mode, default: false

%% Input checks
if ~exist('v','var')
    v = false;
end

%% Start closing
if (v)
    fprintf('%s Closing Scanner...\n', datestr(datetime));
end

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

%% Finish up
if (v)
    fprintf('%s Scanner Closed\n', datestr(datetime));
end
