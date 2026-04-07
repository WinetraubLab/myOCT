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
%   'init'       - Load module, initialize scanner, and optionally initialize translation stage.
%                  yOCTHardware('init', 'OCTSystem', name, 'skipHardware', tf, ...
%                               'octProbePath', path, 'v', tf, ...
%                               'oct2stageXYAngleDeg', deg, ...
%                               'minPosition', vec, 'maxPosition', vec)
%                  octProbePath can be '' when skipHardware=true.
%                  Stage parameters are optional. If hardware is already
%                  initialized, calling init with only stage parameters
%                  connects the stage without re-initializing the OCT system.
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
%   'getStageStatus' - Return current stage position.
%                  [x0, y0, z0] = yOCTHardware('getStageStatus')
%                  Errors if stage was never initialized via init.
%
%   'moveStage'  - Move stage to the given position.
%                  yOCTHardware('moveStage', 'x', mm, 'y', mm, 'z', mm)
%                  Axes not specified default to NaN (not moved).
%                  Optional: yOCTHardware('moveStage', 'z', mm, 'v', true)
%                  Handles coordinate rotation (OCT->Stage) internally.
%
% VALID COMMAND SEQUENCES:
%   Most common:         init (with stage params) -> getStageStatus -> moveStage -> teardown
%   Stage after OCT:     init -> init (stage only) -> getStageStatus -> moveStage -> teardown
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
        'yOCTHardware requires a command: ''init'', ''status'', ''verifyInit'', ''teardown'', ''reset'', ''getStageStatus'', or ''moveStage''.');
end

%% Parse optional name-value parameters
p = inputParser;
addParameter(p, 'OCTSystem', '', @ischar);
addParameter(p, 'skipHardware', false, @islogical);
addParameter(p, 'octProbePath', '', @ischar);
addParameter(p, 'v', false, @islogical);
addParameter(p, 'oct2stageXYAngleDeg', NaN, @isnumeric);
addParameter(p, 'minPosition', [0 0 0], @isnumeric);
addParameter(p, 'maxPosition', [0 0 0], @isnumeric);
addParameter(p, 'x', NaN, @isnumeric);
addParameter(p, 'y', NaN, @isnumeric);
addParameter(p, 'z', NaN, @isnumeric);
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

%  INIT: load module + initialize scanner + optionally initialize stage
case 'init'
    octSystemNameIn = in.OCTSystem;
    skipHw          = in.skipHardware;
    octProbePath    = in.octProbePath;
    oct2stageAngle  = in.oct2stageXYAngleDeg;
    minPos          = in.minPosition;
    maxPos          = in.maxPosition;
    v               = in.v;

    stageRequested = ~isnan(oct2stageAngle);
    octParamsProvided = ~isempty(octSystemNameIn);

    %% Early return if already initialized with same parameters
    if ~isempty(gOCTHardwareStatus.name)
        needOCTReinit = false;

        if octParamsProvided
            nameChanged  = ~strcmpi(octSystemNameIn, gOCTHardwareStatus.name);
            skipChanged  = islogical(skipHw) && skipHw ~= gOCTHardwareStatus.skipHardware;
            probeChanged = ~isempty(octProbePath) && ~isempty(gOCTHardwareStatus.probePath) && ...
                ~strcmp(octProbePath, gOCTHardwareStatus.probePath);
            needOCTReinit = nameChanged || skipChanged || probeChanged;
        end

        if ~needOCTReinit && ~stageRequested
            % Nothing changed, nothing new requested — return current state
            [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
                getOutputs(gOCTHardwareStatus);
            return;
        end

        if needOCTReinit
            % OCT config changed — auto-teardown before re-init
            changed = {};
            if nameChanged,  changed{end+1} = sprintf('OCTSystem: %s -> %s', gOCTHardwareStatus.name, octSystemNameIn); end
            if skipChanged,  changed{end+1} = sprintf('skipHardware: %d -> %d', gOCTHardwareStatus.skipHardware, skipHw); end
            if probeChanged, changed{end+1} = 'octProbePath changed'; end
            if v
                fprintf('%s Configuration changed (%s), tearing down before re-init...\n', ...
                    datestr(datetime), strjoin(changed, ', '));
            end
            yOCTHardware('teardown');
            % Fall through to full init below
        end
        % If only stageRequested (no OCT reinit), skip to stage init below
    end

    %% OCT init (only if not already initialized)
    if isempty(gOCTHardwareStatus.name)
        if ~octParamsProvided
            error('myOCT:yOCTHardware:noSystemName', ...
                'yOCTHardware(''init'') requires OCTSystem (''Ganymede'' or ''Gan632'').');
        end

        validSystems = {'Ganymede', 'Gan632'};
        if ~any(strcmpi(octSystemNameIn, validSystems))
            error('myOCT:yOCTHardware:invalidSystem', ...
                ['Invalid OCT System: %s' newline 'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemNameIn);
        end

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
    end

    %% Stage init (if oct2stageXYAngleDeg was provided)
    if stageRequested
        % Normalize min/max position inputs
        minPos(isnan(minPos)) = 0;
        tmp = zeros(1,3); tmp(1:length(minPos)) = minPos; minPos = tmp;
        maxPos(isnan(maxPos)) = 0;
        tmp = zeros(1,3); tmp(1:length(maxPos)) = maxPos; maxPos = tmp;

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
        gOCTHardwareStatus.stagePosition_OCT = [x0;y0;z0];
        gOCTHardwareStatus.stagePosition_Stage = [x0;y0;z0];
        gOCTHardwareStatus.stageInitialized = true;

        % Motion range test
        if any(minPos ~= maxPos)
            if v
                fprintf('%s Motion Range Test...\n\t(if Matlab is taking more than 2 minutes to finish this step, stage might be at its limit and need to center)\n', datestr(datetime));
            end
            if ~gOCTHardwareStatus.skipHardware
                axes = 'xyz';
                for i = 1:length(axes)
                    if minPos(i) ~= maxPos(i)
                        switch gOCTHardwareStatus.name
                            case 'ganymede'
                                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i) + minPos(i));
                                pause(0.5);
                                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i) + maxPos(i));
                                pause(0.5);
                                ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i));

                            case 'gan632'
                                gOCTHardwareStatus.module.stage.yOCTStageSetPosition_1axis(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i) + minPos(i));
                                pause(0.5);
                                gOCTHardwareStatus.module.stage.yOCTStageSetPosition_1axis(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i) + maxPos(i));
                                pause(0.5);
                                gOCTHardwareStatus.module.stage.yOCTStageSetPosition_1axis(axes(i), ...
                                    gOCTHardwareStatus.stagePosition_Stage(i));

                            otherwise
                                error('Unknown OCT system: %s', gOCTHardwareStatus.name);
                        end
                        pause(0.5);
                    end
                end
            else
                if v
                    fprintf('%s Motion Range Test skipped (skipHardware = true)\n', datestr(datetime));
                end
            end
        end
    end

    %% Return
    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);

%  GETSTAGESTATUS: return stage state
case 'getstagestatus'
    if ~gOCTHardwareStatus.stageInitialized
        error('myOCT:yOCTHardware:stageNotInitialized', ...
            'Stage not initialized. Call yOCTHardware(''init'', ..., ''oct2stageXYAngleDeg'', deg) first.');
    end
    pos = gOCTHardwareStatus.stagePosition_OCT;
    octSystemModule = pos(1);  % x0
    octSystemName   = pos(2);  % y0
    skipHardware    = pos(3);  % z0
    return;

%  MOVESTAGE: move stage to new position (OCT coordinates)
case 'movestage'
    if ~gOCTHardwareStatus.stageInitialized
        error('myOCT:yOCTHardware:stageNotInitialized', ...
            'Stage not initialized. Call yOCTHardware(''init'', ..., ''oct2stageXYAngleDeg'', deg) first.');
    end

    newx = in.x;
    newy = in.y;
    newz = in.z;
    vFlag = in.v;

    % Current positions
    posOCT   = gOCTHardwareStatus.stagePosition_OCT;
    posStage = gOCTHardwareStatus.stagePosition_Stage;
    oct2stageAngle = gOCTHardwareStatus.oct2stageXYAngleDeg;

    % Displacement in OCT coordinates (NaN = don't move that axis)
    d = [newx;newy;newz] - posOCT(:);
    d(isnan(d)) = 0;

    % Rotate displacement into stage coordinate system
    c = cos(oct2stageAngle*pi/180);
    sn = sin(oct2stageAngle*pi/180);
    d_ = [c -sn 0; sn c 0; 0 0 1]*d;

    % Update tracked positions
    posOCT   = posOCT + d;
    posStage = posStage + d_;
    gOCTHardwareStatus.stagePosition_OCT   = posOCT;
    gOCTHardwareStatus.stagePosition_Stage = posStage;

    if vFlag
        fprintf('New Stage Position. ');
        fprintf('At Stage Coordinate System: (%.3f, %.3f, %.3f) mm. ', posStage);
        fprintf('At OCT Coordinate System: (%.3f, %.3f, %.3f) mm.\n', posOCT);
    end

    % Move physical hardware
    if ~gOCTHardwareStatus.skipHardware
        ax = 'xyz';
        for i = 1:3
            if abs(d_(i)) > 0
                switch gOCTHardwareStatus.name
                    case 'ganymede'
                        ThorlabsImagerNET.ThorlabsImager.yOCTStageSetPosition(ax(i), posStage(i));
                    case 'gan632'
                        gOCTHardwareStatus.module.stage.yOCTStageSetPosition_1axis(ax(i), posStage(i));
                    otherwise
                        error('Unknown OCT system: %s', gOCTHardwareStatus.name);
                end
            end
        end
    else
        if vFlag
            fprintf('Stage movement skipped (skipHardware = true)\n');
        end
    end

    [octSystemModule, octSystemName, skipHardware, scannerInitialized] = ...
        getOutputs(gOCTHardwareStatus);
    return;

otherwise
    error('myOCT:yOCTHardware:unknownCommand', ...
        'Unknown command: ''%s''. Use ''init'', ''status'', ''verifyInit'', ''teardown'', ''reset'', ''getStageStatus'', or ''moveStage''.', command);
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
s.stagePosition_OCT      = [0;0;0];
s.stagePosition_Stage    = [0;0;0];
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
