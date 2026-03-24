function [octSystemModule, octSystemName, skipHardware, scannerInitialized] = yOCTHardware(command, varargin)
% Unified OCT hardware manager.
% Handles module loading, scanner initialization, teardown, and state.
%
% OUTPUTS ('status' mode):
%   octSystemModule    - Handle struct for the loaded hardware interface
%   octSystemName      - Lowercase system name (e.g. 'ganymede' or 'gan632')
%   skipHardware       - True when hardware calls are skipped
%   scannerInitialized - True when scanner is currently initialized
%
% COMMANDS:
%   'init'       - Load module and initialize scanner.
%                  yOCTHardware('init', 'OCTSystem', name, 'skipHardware', tf, ...
%                               'octProbePath', path, 'v', tf)
%                  octProbePath can be '' when skipHardware=true.
%
%   'status'     - Return current state without modification.
%                  [module, name, skip, scannerInit] = yOCTHardware('status')
%                  Errors if init was never called.
%
%   'verifyInit' - Verify that init was called and scanner is ready.
%                  Throws an error if hardware is not initialized, or if
%                  skipHardware is false and the scanner has not been opened.
%                  yOCTHardware('verifyInit')
%
%   'teardown'   - Close scanner, close hardware, terminate Python (Gan632),
%                  reset state.
%                  yOCTHardware('teardown')
%                  Optional: yOCTHardware('teardown', 'v', true)
%
%   'reset'      - Clear all persistent variables without closing hardware.
%                  yOCTHardware('reset')
%
% VALID COMMAND SEQUENCES:
%   Most common:         init -> status -> teardown
%   With state reset:    init -> status -> reset -> init -> teardown
%   WARNING: init -> reset -> [no teardown]: leaves hardware open. Always end with teardown.


%% Persistent state (single source of truth)
persistent gOCTHardwareStatus;
if isempty(gOCTHardwareStatus)
    gOCTHardwareStatus = resetGlobalStruct();
end

%% Parse command
if ~exist('command','var') || isempty(command)
    error('myOCT:yOCTHardware:noCommand', ...
        'yOCTHardware requires a command: ''init'', ''status'', ''verifyInit'', ''teardown'', or ''reset''.');
end

%% Parse optional name-value parameters
p = inputParser;
addParameter(p, 'OCTSystem', '', @ischar);
addParameter(p, 'skipHardware', false, @islogical);
addParameter(p, 'octProbePath', '', @ischar);
addParameter(p, 'v', false, @islogical);
parse(p, varargin{:});
in = p.Results;

%% Command dispatch
switch lower(command)

%  RESET: clear state without closing hardware
case 'reset'
    gOCTHardwareStatus = resetGlobalStruct();
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  STATUS: return current state (read only)
case 'status'
    if isempty(gOCTHardwareStatus.name)
        error('myOCT:yOCTHardware:notInitialized', ...
            'Hardware not initialized. Call yOCTHardware(''init'', ...) first.');
    end
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  VERIFYINIT: guard — errors if not ready for hardware operations
case 'verifyinit'
    if isempty(gOCTHardwareStatus.name)
        error('myOCT:yOCTHardware:notInitialized', ...
            'Hardware not initialized. Call yOCTHardware(''init'', ...) first.');
    end
    if ~gOCTHardwareStatus.skipHardware && ~gOCTHardwareStatus.scannerInitialized
        error('myOCT:yOCTHardware:scannerNotInitialized', ...
            'Scanner is not initialized. Call yOCTHardware(''init'', ...) with octProbePath.');
    end
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  TEARDOWN: close scanner, close hardware, terminate Python, reset
case 'teardown'
    v = in.v;

    % If never initialized, nothing to tear down
    if isempty(gOCTHardwareStatus.name)
        [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
            getOutputs(gOCTHardwareStatus);
        return;
    end

    % Close scanner if hardware is active
    if ~gOCTHardwareStatus.skipHardware
        if v
            fprintf('%s Closing hardware connections...\n', datestr(datetime));
        end

        % yOCTHardware_closeScanner only sends the close-scanner command to
        % the SDK.  The teardown block here additionally handles
        % Gan632-specific Python cleanup and interpreter termination.
        yOCTHardware_closeScanner(v);

        switch gOCTHardwareStatus.name
            case 'gan632'
                % Gan632: close all hardware (stages + scanner) via Python cleanup
                try
                    gOCTHardwareStatus.module.cleanup.yOCTCloseAllHardware();
                catch ME
                    if v
                        warning('Error during Gan632 cleanup: %s', ME.message);
                    end
                end
        end
    end

    % Terminate Python interpreter for Gan632
    if strcmpi(gOCTHardwareStatus.name, 'gan632')
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
    elseif strcmpi(gOCTHardwareStatus.name, 'ganymede')
        if v
            fprintf('%s Ganymede cleanup complete.\n', datestr(datetime));
        end
    end

    % Clear all persistent state
    gOCTHardwareStatus = resetGlobalStruct();
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  INIT: load module + initialize scanner
case 'init'
    octSystemNameIn = in.OCTSystem;
    skipHw          = in.skipHardware;
    octProbePath    = in.octProbePath;
    v               = in.v;

    %% Early return if already initialized with same parameters
    if ~isempty(gOCTHardwareStatus.name)
        nameChanged  = ~isempty(octSystemNameIn) && ~strcmpi(octSystemNameIn, gOCTHardwareStatus.name);
        skipChanged  = islogical(skipHw) && skipHw ~= gOCTHardwareStatus.skipHardware;
        probeChanged = ~isempty(octProbePath) && ~isempty(gOCTHardwareStatus.probePath) && ...
            ~strcmp(octProbePath, gOCTHardwareStatus.probePath);

        if ~nameChanged && ~skipChanged && ~probeChanged
            % Everything matches — return current state
            [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
                getOutputs(gOCTHardwareStatus);
            return;
        end

        % Something changed — auto-teardown before re-init
        changed = {};
        if nameChanged,  changed{end+1} = sprintf('OCTSystem: %s -> %s', gOCTHardwareStatus.name, octSystemNameIn); end
        if skipChanged,  changed{end+1} = sprintf('skipHardware: %d -> %d', gOCTHardwareStatus.skipHardware, skipHw); end
        if probeChanged, changed{end+1} = 'octProbePath changed'; end
        if v
            fprintf('%s Configuration changed (%s), tearing down before re-init...\n', ...
                datestr(datetime), strjoin(changed, ', '));
        end
        yOCTHardware('teardown');
    end

    %% Validate inputs
    if isempty(octSystemNameIn)
        error('myOCT:yOCTHardware:noSystemName', ...
            'yOCTHardware(''init'') requires OCTSystem (''Ganymede'' or ''Gan632'').');
    end

    validSystems = {'Ganymede', 'Gan632'};
    if ~any(strcmpi(octSystemNameIn, validSystems))
        error('myOCT:yOCTHardware:invalidSystem', ...
            ['Invalid OCT System: %s' newline 'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemNameIn);
    end

    %% skipHardware path: store state and return (no module, no scanner)
    if skipHw
        gOCTHardwareStatus.name              = lower(octSystemNameIn);
        gOCTHardwareStatus.module            = [];
        gOCTHardwareStatus.skipHardware      = true;
        gOCTHardwareStatus.probePath         = octProbePath;
        gOCTHardwareStatus.scannerInitialized = false;

        [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
            getOutputs(gOCTHardwareStatus);
        return;
    end

    %% Load hardware module
    octSystemNameIn = lower(octSystemNameIn);
    gOCTHardwareStatus.module = loadModule(octSystemNameIn, v);

    %% Store state
    gOCTHardwareStatus.name         = octSystemNameIn;
    gOCTHardwareStatus.skipHardware = false;
    gOCTHardwareStatus.probePath    = octProbePath;

    %% Initialize scanner (only when octProbePath is provided)
    if ~isempty(octProbePath)
        yOCTHardware_initScanner(octProbePath, v);
        gOCTHardwareStatus.scannerInitialized = true;
    else
        gOCTHardwareStatus.scannerInitialized = false;
    end

    %% Return
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);

otherwise
    error('myOCT:yOCTHardware:unknownCommand', ...
        'Unknown command: ''%s''. Use ''init'', ''status'', ''verifyInit'', ''teardown'', or ''reset''.', command);
end

end

%% Local helpers

function s = resetGlobalStruct()
%RESETGLOBALSTRUCT Return a clean default state struct.
s.module            = [];
s.name              = '';
s.skipHardware      = false;
s.probePath         = '';
s.scannerInitialized = false;
end

function [octSystemModule, octSystemName, skipHardware, scannerInitialized] = getOutputs(s)
%GETOUTPUTS Map state struct fields to the function's output variables.
octSystemModule    = s.module;
octSystemName      = s.name;
skipHardware       = s.skipHardware;
scannerInitialized = s.scannerInitialized;
end

function module = loadModule(systemName, v)
%LOADMODULE Load the OCT hardware module for the given system.
switch systemName
    case 'ganymede'
        % Ganymede: C# library
        currentFileFolder = fileparts(mfilename('fullpath'));
        libFolder = [currentFileFolder '\Lib\'];

        % Check if DLL is already loaded in memory (persists across teardown)
        if ~isempty(which('ThorlabsImagerNET.ThorlabsImager'))
            asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
            module = asm;
            if v
                fprintf('%s ThorlabsImagerNET already loaded. Using existing instance. To fully reset, restart MATLAB.\n', datestr(datetime));
            end
        else
            % First-time load: copy sub-library DLLs if needed
            if ~exist([libFolder 'SpectralRadar.dll'],'file')
                copyfile([libFolder 'LaserDiode\*.*'],libFolder,'f');
                copyfile([libFolder 'MotorController\*.*'],libFolder,'f');
                copyfile([libFolder 'ThorlabsOCT\*.*'],libFolder,'f');
            end

            asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
            module = asm;
        end

    case 'gan632'
        % Gan632: Python SDK (pyspectralradar)

        % Configure Python environment (out-of-process for SDK robustness)
        try
            pe = pyenv;
            if pe.Status ~= "NotLoaded"
                needsRestart = false;
                if isprop(pe, 'ExecutionMode')
                    if ~strcmp(pe.ExecutionMode, 'OutOfProcess')
                        needsRestart = true;
                    end
                end

                if needsRestart
                    if v
                        fprintf('%s Restarting Python in OutOfProcess mode for SDK robustness...\n', datestr(datetime));
                    end
                    terminate(pyenv);
                    pyenv('ExecutionMode', 'OutOfProcess');
                end
            else
                if isprop(pyenv, 'ExecutionMode')
                    pyenv('ExecutionMode', 'OutOfProcess');
                end
            end
        catch
            if v
                warning('Could not configure out-of-process Python. Using in-process mode.');
            end
        end

        % Import Python modules
        repoPath = fullfile(fileparts(mfilename('fullpath')), 'ThorlabsImagerPython');

        module = struct();
        module.oct = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_oct', ...
            'repoName', repoPath, ...
            'v', v);
        module.stage = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_stage', ...
            'repoName', repoPath, ...
            'v', v);
        module.cleanup = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_cleanup', ...
            'repoName', repoPath, ...
            'v', v);

    otherwise
        error('This should never happen');
end
end
