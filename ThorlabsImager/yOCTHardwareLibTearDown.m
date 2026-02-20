function yOCTHardwareLibTearDown(v)
% Tear down hardware library and clean up resources.
% Closes all hardware connections (stages + scanner) and terminates Python interpreter for Gan632.
% Must be called after yOCTHardwareLibSetUp().
%
%   INPUTS:
%       v: Verbose mode (default: false)

%% Input checks
if ~exist('v','var')
    v = false;
end

% Get system info from persistent library (must have been set up first)
% If SetUp was never called the cache is empty: nothing to tear down.
try
    [octSystemModule, octSystemName, skipHardware] = yOCTHardwareLibSetUp();
catch
    return;
end

%% Close hardware connections first
if ~skipHardware
    if v
        fprintf('%s Closing hardware connections...\n', datestr(datetime));
    end
    
    switch(lower(octSystemName))
        case 'ganymede'
            % Ganymede: C# DLL - close scanner only
            
        case 'gan632'
            % Gan632: Python SDK - close all hardware (stages + scanner)
            octSystemModule.cleanup.yOCTCloseAllHardware();
            
        otherwise
            if v
                warning('Unknown OCT system: %s', octSystemName);
            end
    end
    
    % Reset scanner state since we're tearing down
    yOCTScannerStateSet(false);
end

%% Tear down library environment
if strcmpi(octSystemName, 'Gan632')
    % Gan632: Terminate Python interpreter for clean USB device state
    % This ensures SpectralRadar SDK releases all resources
    % Comment out if you want faster reruns (but may require hardware power cycle)
    
    % Terminate Python interpreter
    try
        terminate(pyenv);
    catch ME
        if v
            warning('Failed to terminate Python interpreter: %s', ME.message);
        end
    end
    
    if v
        fprintf('%s Gan632 cleanup complete.\n', datestr(datetime));
    end
    
elseif strcmpi(octSystemName, 'Ganymede')
    % Ganymede: C# cleanup (if needed in future)
    if v
        fprintf('%s Ganymede cleanup complete.\n', datestr(datetime));
    end
    
else
    if v
        warning('Unknown OCT system: %s. No teardown performed.', octSystemName);
    end
end

%% Clear SetUp cache so the next run re-initializes from scratch
% Without this, SetUp would return a stale (potentially dead) module reference.
yOCTHardwareLibSetUp('reset');

end
