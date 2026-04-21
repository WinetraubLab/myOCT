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
%   'init'       - Load hardware module, initialize scanner, and initialize
%                  translation stage.
%                  yOCTHardware('init', 'OCTSystem', name, ...)
%                  Parameters:
%                    OCTSystem            - System name: 'Ganymede' or 'Gan632'. Required.
%                    octProbePath         - Path to the probe .ini file. Required unless skipHardware=true.
%                    oct2stageXYAngleDeg  - (default NaN) Override for the stage rotation angle in degrees.
%                    skipHardware         - (default false) If true, skips all hardware calls (scanner + stage).
%                    v                    - (default false) Verbose logging.
%
%   'status'     - Verify init was called and return current state. Errors if 'init' was never called,
%                  or if hardware is active (skipHardware=false) but the scanner was never opened.
%                  [module, name, skip, scannerInit] = yOCTHardware('status')
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

% Stage position globals shared with yOCTStageMoveTo
global goct2stageXYAngleDeg;
global gStageCurrentStagePosition_OCTCoordinates;
global gStageCurrentStagePosition_StageCoordinates;

%% Parse command
if ~exist('command','var') || isempty(command)
    error('myOCT:yOCTHardware:noCommand', ...
        'yOCTHardware requires a command: ''init'', ''status'', ''teardown'', or ''reset''.');
end

%% Parse optional name-value parameters
p = inputParser;
addParameter(p, 'OCTSystem', '', @ischar);
addParameter(p, 'skipHardware', false, @islogical);
addParameter(p, 'octProbePath', '', @ischar);
addParameter(p, 'v', false, @islogical);
addParameter(p, 'oct2stageXYAngleDeg', NaN, @isnumeric);
parse(p, varargin{:});
in = p.Results;

%% Command dispatch
switch lower(command)

%  RESET: clear state without closing hardware
case 'reset'
    gOCTHardwareStatus = resetGlobalStruct();
    clearStageGlobals();
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  STATUS: verify 'init' was called + scanner ready, then return current state
case 'status'
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
                        warning(ME.identifier, '%s', ME.message);
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
                warning(ME.identifier, '%s', ME.message);
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
    clearStageGlobals();
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

%  INIT: load module + initialize scanner + initialize stage
case 'init'
    octSystemNameIn = in.OCTSystem;
    skipHw          = in.skipHardware;
    octProbePath    = in.octProbePath;
    oct2stageAngle  = in.oct2stageXYAngleDeg;
    v               = in.v;

    %% Validate required inputs
    if isempty(octSystemNameIn)
        error('myOCT:yOCTHardware:noSystemName', ...
            'yOCTHardware(''init'') requires OCTSystem (''Ganymede'' or ''Gan632'').');
    end

    %% If stage angle was not provided explicitly, read it from the probe INI.
    % This lets demos and scripts init everything in a single call without
    % needing to parse the INI themselves.
    if isnan(oct2stageAngle) && ~isempty(octProbePath) && exist(octProbePath, 'file')
        probeIni = yOCTReadProbeIniToStruct(octProbePath);
        oct2stageAngle = probeIni.Oct2StageXYAngleDeg;
    end
    stageRequested = ~isnan(oct2stageAngle);

    %% Early return if already initialized with the same parameters
    if ~isempty(gOCTHardwareStatus.name)
        nameChanged  = ~strcmpi(octSystemNameIn, gOCTHardwareStatus.name);
        skipChanged  = islogical(skipHw) && skipHw ~= gOCTHardwareStatus.skipHardware;
        probeChanged = ~isempty(octProbePath) && ~isempty(gOCTHardwareStatus.probePath) && ...
            ~strcmp(octProbePath, gOCTHardwareStatus.probePath);
        stageChanged = stageRequested && ~gOCTHardwareStatus.stageInitialized;

        if ~nameChanged && ~skipChanged && ~probeChanged && ~stageChanged
            % Everything matches — return current state
            [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
                getOutputs(gOCTHardwareStatus);
            return;
        end

        % Something changed: auto-teardown before re-init
        changed = {};
        if nameChanged,  changed{end+1} = sprintf('OCTSystem: %s -> %s', gOCTHardwareStatus.name, octSystemNameIn); end
        if skipChanged,  changed{end+1} = sprintf('skipHardware: %d -> %d', gOCTHardwareStatus.skipHardware, skipHw); end
        if probeChanged, changed{end+1} = 'octProbePath changed'; end
        if stageChanged, changed{end+1} = 'stage requested'; end
        if v
            fprintf('%s Configuration changed (%s), tearing down before re-init...\n', ...
                datestr(datetime), strjoin(changed, ', '));
        end
        yOCTHardware('teardown');
    end

    validSystems = {'Ganymede', 'Gan632'};
    if ~any(strcmpi(octSystemNameIn, validSystems))
        error('myOCT:yOCTHardware:invalidSystem', ...
            ['Invalid OCT System: %s' newline 'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemNameIn);
    end

    %% OCT init
    if skipHw
        gOCTHardwareStatus.name              = lower(octSystemNameIn);
        gOCTHardwareStatus.module            = [];
        gOCTHardwareStatus.skipHardware      = true;
        gOCTHardwareStatus.probePath         = octProbePath;
        gOCTHardwareStatus.scannerInitialized = false;
    else
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
    end

    %% Stage init (only when oct2stageXYAngleDeg is known)
    if stageRequested
        if v
            fprintf('%s Initialzing Stage Hardware...\n\t(if Matlab is taking more than 2 minutes to finish this step, restart hardware and try again)\n', datestr(datetime));
        end

        % Initialize stage axes
        if ~gOCTHardwareStatus.skipHardware
            switch gOCTHardwareStatus.name
                case 'ganymede'
                    if v
                        fprintf('%s [Ganymede] Initializing C# DLL-based stage control (3 axes)...\n', datestr(datetime));
                    end
                    z0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('z');
                    x0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('x');
                    y0 = ThorlabsImagerNET.ThorlabsImager.yOCTStageInit('y');

                case 'gan632'
                    if v
                        fprintf('%s [Gan632] Initializing Python-based stage control (3 axes)...\n', datestr(datetime));
                    end
                    z0 = gOCTHardwareStatus.module.stage.yOCTStageInit_1axis('z');
                    x0 = gOCTHardwareStatus.module.stage.yOCTStageInit_1axis('x');
                    y0 = gOCTHardwareStatus.module.stage.yOCTStageInit_1axis('y');

                otherwise
                    error('Unknown OCT system: %s', gOCTHardwareStatus.name);
            end
        else
            if v
                fprintf('%s Stage initialization skipped (skipHardware = true), using origin (0,0,0)\n', datestr(datetime));
            end
            x0 = 0; y0 = 0; z0 = 0;
        end

        % Store stage state
        gOCTHardwareStatus.oct2stageXYAngleDeg = oct2stageAngle;
        gOCTHardwareStatus.stageInitialized = true;

        % Write to globals (shared with yOCTStageMoveTo)
        goct2stageXYAngleDeg = oct2stageAngle;
        gStageCurrentStagePosition_OCTCoordinates = [x0;y0;z0];
        gStageCurrentStagePosition_StageCoordinates = [x0;y0;z0];
    end

    %% Return
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);

otherwise
    error('myOCT:yOCTHardware:unknownCommand', ...
        'Unknown command: ''%s''. Use ''init'', ''status'', ''teardown'', or ''reset''.', command);
end

end

%% Local helpers

function s = resetGlobalStruct()
%RESETGLOBALSTRUCT Return a clean default state struct.
s.module            = [];
s.name              = '';
s.skipHardware      = false;
s.probePath              = '';
s.scannerInitialized     = false;
s.stageInitialized       = false;
s.oct2stageXYAngleDeg    = 0;
end

function clearStageGlobals()
%CLEARSTAGEGLOBALS Reset stage globals shared with yOCTStageMoveTo.
global goct2stageXYAngleDeg;
global gStageCurrentStagePosition_OCTCoordinates;
global gStageCurrentStagePosition_StageCoordinates;
global gRegisteredMotionRangeMin_OCT;
global gRegisteredMotionRangeMax_OCT;
goct2stageXYAngleDeg = [];
gStageCurrentStagePosition_OCTCoordinates = [];
gStageCurrentStagePosition_StageCoordinates = [];
gRegisteredMotionRangeMin_OCT = [];
gRegisteredMotionRangeMax_OCT = [];
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
