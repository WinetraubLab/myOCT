function [octSystemModule, octSystemName, skipHardware, scannerInitialized] = yOCTHardware(command, octSystemName, skipHardware, octProbePath, v)
% Unified OCT hardware manager.
% Handles module loading, scanner initialization, teardown, and state.
%
% COMMANDS:
%   'init'     - Load module and initialize scanner.
%                yOCTHardware('init', octSystemName, skipHardware, octProbePath, verbose)
%                octProbePath can be '' when skipHardware=true.
%
%   'status'   - Return cached state without modification.
%                [module, name, skip, scannerInit] = yOCTHardware('status')
%                Errors if init was never called.
%
%   'teardown' - Close scanner, close hardware, terminate Python (Gan632), reset cache.
%                yOCTHardware('teardown')
%
%   'reset'    - Clear all persistent variables without closing hardware.
%                yOCTHardware('reset')
%
% OUTPUTS:
%   octSystemModule    - Handle struct for the loaded hardware interface
%   octSystemName      - Lowercase system name (e.g. 'ganymede' or 'gan632')
%   skipHardware       - True when hardware calls are skipped
%   scannerInitialized - True when scanner is currently initialized

%% Persistent state (single source of truth)
persistent gOCTSystemModule;
persistent gOCTSystemName;
persistent gSkipHardware;
persistent gOCTProbePath;
persistent gVerbose;
persistent gScannerInitialized;

%% Input defaults
if ~exist('command','var') || isempty(command)
    error('myOCT:yOCTHardware:noCommand', ...
        'yOCTHardware requires a command: ''init'', ''status'', ''teardown'', or ''reset''.');
end
if ~exist('octSystemName','var'), octSystemName = ''; end
if ~exist('skipHardware','var'),  skipHardware = false; end
if ~exist('octProbePath','var'),  octProbePath = ''; end
if ~exist('v','var'),             v = false; end

%% Command dispatch
switch lower(command)

%  RESET: clear cache without closing hardware
case 'reset'
    gOCTSystemModule = [];
    gOCTSystemName   = [];
    gSkipHardware    = [];
    gOCTProbePath    = [];
    gVerbose         = [];
    gScannerInitialized = false;
    octSystemModule  = [];
    octSystemName    = '';
    skipHardware     = false;
    scannerInitialized = false;
    return;

%  STATUS: return cached state (read only)
case 'status'
    if isempty(gOCTSystemName)
        error('myOCT:yOCTHardware:notInitialized', ...
            'Hardware not initialized. Call yOCTHardware(''init'', ...) first.');
    end
    octSystemModule = gOCTSystemModule;
    octSystemName   = gOCTSystemName;
    skipHardware    = gSkipHardware;
    scannerInitialized = ~isempty(gScannerInitialized) && gScannerInitialized;
    return;

%  TEARDOWN: close scanner, close hardware, terminate Python, reset
case 'teardown'
    % Use cached verbose if caller didn't pass one
    if ~v && ~isempty(gVerbose)
        v = gVerbose;
    end

    % If never initialized, nothing to tear down
    if isempty(gOCTSystemName)
        octSystemModule = [];
        octSystemName   = '';
        skipHardware    = false;
        scannerInitialized = false;
        return;
    end

    % Close scanner if hardware is active
    if ~gSkipHardware
        if v
            fprintf('%s Closing hardware connections...\n', datestr(datetime));
        end

        % Close scanner via the MATLAB wrapper (handles both systems)
        yOCTScannerClose(v);

        switch gOCTSystemName
            case 'gan632'
                % Gan632: close all hardware (stages + scanner) via Python cleanup
                try
                    gOCTSystemModule.cleanup.yOCTCloseAllHardware();
                catch ME
                    if v
                        warning('Error during Gan632 cleanup: %s', ME.message);
                    end
                end
        end
    end

    % Reset scanner state
    gScannerInitialized = false;

    % Terminate Python interpreter for Gan632
    if strcmpi(gOCTSystemName, 'gan632')
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
    elseif strcmpi(gOCTSystemName, 'ganymede')
        if v
            fprintf('%s Ganymede cleanup complete.\n', datestr(datetime));
        end
    end

    % Clear all persistent state
    gOCTSystemModule = [];
    gOCTSystemName   = [];
    gSkipHardware    = [];
    gOCTProbePath    = [];
    gVerbose         = [];
    gScannerInitialized = false;

    octSystemModule = [];
    octSystemName   = '';
    skipHardware    = false;
    scannerInitialized = false;
    return;

%  INIT: load module + initialize scanner
case 'init'
    % Store verbose for reuse in teardown
    if v
        gVerbose = true;
    elseif isempty(gVerbose)
        gVerbose = false;
    end

    %% Early return if already initialized with same parameters
    if ~isempty(gOCTSystemName)
        nameChanged = ~isempty(octSystemName) && ~strcmpi(octSystemName, gOCTSystemName);
        skipChanged = islogical(skipHardware) && skipHardware ~= gSkipHardware;
        probeChanged = ~isempty(octProbePath) && ~isempty(gOCTProbePath) && ~strcmp(octProbePath, gOCTProbePath);

        if ~nameChanged && ~skipChanged && ~probeChanged
            % Everything matches — return cached state
            octSystemModule = gOCTSystemModule;
            octSystemName   = gOCTSystemName;
            skipHardware    = gSkipHardware;
            scannerInitialized = ~isempty(gScannerInitialized) && gScannerInitialized;
            return;
        end

        % Something changed — auto-teardown before re-init
        if v
            fprintf('%s Configuration changed, tearing down before re-init...\n', datestr(datetime));
        end
        yOCTHardware('teardown');
    end

    %% Validate inputs
    if isempty(octSystemName)
        error('myOCT:yOCTHardware:noSystemName', ...
            'yOCTHardware(''init'') requires octSystemName (''Ganymede'' or ''Gan632'').');
    end

    validSystems = {'Ganymede', 'Gan632'};
    if ~any(strcmpi(octSystemName, validSystems))
        error('myOCT:yOCTHardware:invalidSystem', ...
            ['Invalid OCT System: %s' newline 'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemName);
    end

    %% skipHardware path: cache state and return (no module, no scanner)
    if skipHardware
        gOCTSystemName   = lower(octSystemName);
        gOCTSystemModule = [];
        gSkipHardware    = true;
        gOCTProbePath    = octProbePath;

        octSystemModule = gOCTSystemModule;
        octSystemName   = gOCTSystemName;
        skipHardware    = gSkipHardware;
        scannerInitialized = false;
        return;
    end

    %% Load hardware module
    octSystemName = lower(octSystemName);

    switch octSystemName
        case 'ganymede'
            % Ganymede: C# library
            currentFileFolder = fileparts(mfilename('fullpath'));
            libFolder = [currentFileFolder '\Lib\'];

            % Check if DLL is already loaded in memory (persists across teardown)
            if ~isempty(which('ThorlabsImagerNET.ThorlabsImager'))
                asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
                gOCTSystemModule = asm;
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
                gOCTSystemModule = asm;
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

            gOCTSystemModule = struct();
            gOCTSystemModule.oct = yOCTImportPythonModule(...
                'packageName', 'thorlabs_imager_oct', ...
                'repoName', repoPath, ...
                'v', v);
            gOCTSystemModule.stage = yOCTImportPythonModule(...
                'packageName', 'thorlabs_imager_stage', ...
                'repoName', repoPath, ...
                'v', v);
            gOCTSystemModule.cleanup = yOCTImportPythonModule(...
                'packageName', 'thorlabs_imager_cleanup', ...
                'repoName', repoPath, ...
                'v', v);

        otherwise
            error('This should never happen');
    end

    %% Cache state
    gOCTSystemName = octSystemName;
    gSkipHardware  = false;
    gOCTProbePath  = octProbePath;

    %% Initialize scanner (only when octProbePath is provided)
    if ~isempty(octProbePath)
        yOCTScannerInit(octProbePath, v);
        gScannerInitialized = true;
    else
        gScannerInitialized = false;
    end

    %% Return
    octSystemModule = gOCTSystemModule;
    octSystemName   = gOCTSystemName;
    skipHardware    = gSkipHardware;
    scannerInitialized = gScannerInitialized;

otherwise
    error('myOCT:yOCTHardware:unknownCommand', ...
        'Unknown command: ''%s''. Use ''init'', ''status'', ''teardown'', or ''reset''.', command);
end

end
