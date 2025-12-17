function yOCTHardwareLibTearDown(octSystemName, v)
% Tear down hardware library and clean up resources.
% Closes all hardware connections (stages + scanner) and terminates Python interpreter for Gan632.
%
%   INPUTS:
%       octSystemName: Name of the OCT system ('Ganymede' or 'Gan632')
%                      Can also be called without arguments if library already loaded.
%       v: Verbose mode (default: false)

%% Input checks
if ~exist('octSystemName','var') || isempty(octSystemName)
    % If no octSystemName provided, get it from persistent library
    [octSystemModule, octSystemName, skipHardware] = yOCTHardwareLibSetUp();
else
    % Load library to get module handle
    [octSystemModule, ~, skipHardware] = yOCTHardwareLibSetUp();
end

if ~exist('v','var')
    v = false;
end

%% Close hardware connections first
if ~skipHardware
    if v
        fprintf('Closing hardware connections...\n');
    end
    
    switch(lower(octSystemName))
        case 'ganymede'
            % Ganymede: C# DLL - close scanner only
            yOCTScannerClose(v);
            
        case 'gan632'
            % Gan632: Python SDK - close all hardware (stages + scanner)
            octSystemModule.cleanup.yOCTCloseAllHardware();
            
        otherwise
            if v
                warning('Unknown OCT system: %s', octSystemName);
            end
    end
end

%% Tear down library environment
if strcmpi(octSystemName, 'Gan632')
    % Gan632: Terminate Python interpreter for clean USB device state
    % This ensures SpectralRadar SDK releases all resources
    % Comment out if you want faster reruns (but may require hardware power cycle)
    
    if v
        fprintf('Cleaning up Gan632 Python environment...\n');
    end
    
    % Clear function handles
    clear functions
    
    % Terminate Python interpreter
    try
        terminate(pyenv);
        if v
            fprintf('Python interpreter terminated successfully.\n');
        end
    catch ME
        if v
            warning('Failed to terminate Python interpreter: %s', ME.message);
        end
    end
    
elseif strcmpi(octSystemName, 'Ganymede')
    % Ganymede: C# cleanup (if needed in future)
    if v
        fprintf('Ganymede cleanup complete.\n');
    end
    
else
    if v
        warning('Unknown OCT system: %s. No teardown performed.', octSystemName);
    end
end

end
