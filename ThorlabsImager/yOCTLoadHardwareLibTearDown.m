function yOCTLoadHardwareLibTearDown(octSystemName, v)
% Tear down hardware library and clean up resources.
% For Gan632 systems, this terminates the Python interpreter to ensure
% clean USB device state for the SpectralRadar SDK.
%
%   INPUTS:
%       octSystemName: Name of the OCT system ('Ganymede' or 'Gan632')
%       v: Verbose mode (default: false)

%% Input checks
if ~exist('v','var')
    v = false;
end

%% Tear down based on system type
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
