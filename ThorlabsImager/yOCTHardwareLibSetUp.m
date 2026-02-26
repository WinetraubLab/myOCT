function [octSystemModule, octSystemName, skipHardware] = yOCTHardwareLibSetUp(octSystemName, skipHardware, v)
% Load and return the hardware interface library for an OCT system.
% This function also configures the Python environment for Gan632 systems.
%
%   INPUTS:
%       octSystemName: Name of the OCT system to load. 
%           Supported values: 'Ganymede', 'Gan632'. 
%           Default: '' (empty, only valid if library is already loaded)
%       skipHardware: When set to true, will skip hardware initialization.
%           Default: false
%       v: Verbose mode. 
%           Default: false
%
%   OUTPUT:
%       octSystemModule - Handle or structure representing the loaded 
%                         hardware interface library.

%% Input checks
if ~exist('octSystemName','var')
    octSystemName = '';
end

if ~exist('skipHardware','var')
    skipHardware = false;
end

if ~exist('v','var')
    v = false;
end

%% Check if library is already loaded (early return)
if yOCTHardwareState('isLoaded')
    % Detect whether the caller explicitly requests a different system
    % name or a different skipHardware mode. If changed (any), clear
    % the cache and fall through to re initialization with new values.
    cachedName = yOCTHardwareState('get', 'systemName');
    cachedSkip = yOCTHardwareState('get', 'skipHardware');

    systemNameChanged = nargin >= 1 && ~isempty(octSystemName) && ...
                        ~strcmpi(octSystemName, cachedName);
    skipChanged       = nargin >= 2 && islogical(skipHardware) && ...
                        skipHardware ~= cachedSkip;

    if systemNameChanged || skipChanged
        % Stale cache: wipe and fall through to full init
        yOCTHardwareState('reset');
    else
        % Cache is valid: return cached values
        octSystemModule = yOCTHardwareState('get', 'systemModule');
        octSystemName   = yOCTHardwareState('get', 'systemName');
        skipHardware    = yOCTHardwareState('get', 'skipHardware');
        return;
    end
end

%% Validate inputs that are only needed for first-time load
if isempty(octSystemName)
    error('myOCT:yOCTHardwareLibSetUp:noSystemName', ...
          "yOCTHardwareLibSetUp must be called with a valid 'octSystemName' the first time it is executed.");
end

validSystems = {'Ganymede', 'Gan632'};
if ~any(strcmpi(octSystemName, validSystems))
    error(['Invalid OCT System: %s' newline ...
           'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemName);
end

%% Skip hardware path
if skipHardware
    yOCTHardwareState('set', 'systemName',   lower(octSystemName));
    yOCTHardwareState('set', 'systemModule', []);
    yOCTHardwareState('set', 'skipHardware', true);

    % Return cached values
    octSystemModule = yOCTHardwareState('get', 'systemModule');
    octSystemName   = yOCTHardwareState('get', 'systemName');
    skipHardware    = yOCTHardwareState('get', 'skipHardware');
    return;
else
    yOCTHardwareState('set', 'skipHardware', false);
end

%% Initialize library based on system type
octSystemName = lower(octSystemName);

switch(octSystemName)
    case 'ganymede'
        % Ganymede: C# library 
    
        % Find the folder that c# dll is at.
        currentFileFolder = fileparts(mfilename('fullpath'));
	    libFolder = [currentFileFolder '\Lib\'];
        
        % Verify that library wasn't loaded before. If so, reuse without re-initializing
        if ~isempty(which('ThorlabsImagerNET.ThorlabsImager'))
            % DLL already in memory: get existing reference
            asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
            yOCTHardwareState('set', 'systemModule', asm);
            yOCTHardwareState('set', 'systemName',   lower(octSystemName));
            octSystemModule = yOCTHardwareState('get', 'systemModule');
            octSystemName   = yOCTHardwareState('get', 'systemName');
            skipHardware    = yOCTHardwareState('get', 'skipHardware');
            if v
                fprintf('%s ThorlabsImagerNET already loaded. Using existing instance. To fully reset, restart MATLAB.\n', datestr(datetime));
            end
            return;
        end
	    
	    if ~exist([libFolder 'SpectralRadar.dll'],'file')
		    % Copy Subfolders to main lib folder
		    copyfile([libFolder 'LaserDiode\*.*'],libFolder,'f');
		    copyfile([libFolder 'MotorController\*.*'],libFolder,'f');
		    copyfile([libFolder 'ThorlabsOCT\*.*'],libFolder,'f');
	    end
        
        % Load Assembly (first time only)
        asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
    
        % Mark assembly as loaded
        yOCTHardwareState('set', 'systemModule', asm); 
        
    case 'gan632'
        % Gan632: Python SDK (pyspectralradar)
        
        % Configure Python environment (force out-of-process mode for SDK robustness)
        % This prevents native extension (PySpectralRadar, XA SDK) problems from crashing MATLAB
        try
            pe = pyenv;
            if pe.Status ~= "NotLoaded"
                % Check if we need to restart or change execution mode
                needsRestart = false;
                if isprop(pe, 'ExecutionMode')
                    % MATLAB R2019b+ supports out-of-process execution
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
                % Python not loaded yet, set mode before first load
                if isprop(pyenv, 'ExecutionMode')
                    pyenv('ExecutionMode', 'OutOfProcess');
                end
            end
        catch
            % pyenv not available (older MATLAB), continue with in-process
            if v
                warning('Could not configure out-of-process Python. Using in-process mode.');
            end
        end
        
        % Import each module separately for clarity
        repoPath = fullfile(fileparts(mfilename('fullpath')), 'ThorlabsImagerPython');
        
        moduleStruct = struct();
        moduleStruct.oct = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_oct', ...
            'repoName', repoPath, ...
            'v', v);
        moduleStruct.stage = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_stage', ...
            'repoName', repoPath, ...
            'v', v);
        moduleStruct.cleanup = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_cleanup', ...
            'repoName', repoPath, ...
            'v', v);
        yOCTHardwareState('set', 'systemModule', moduleStruct);
        
    otherwise
        error('This should never happen')
end

yOCTHardwareState('set', 'systemName', lower(octSystemName));

%% Return 
octSystemModule = yOCTHardwareState('get', 'systemModule');
octSystemName   = yOCTHardwareState('get', 'systemName');
skipHardware    = yOCTHardwareState('get', 'skipHardware');
end
