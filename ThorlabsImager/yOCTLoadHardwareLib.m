function [octSystemModule, octSystemName, skipHardware] = yOCTLoadHardwareLib(octSystemName, skipHardware, v)
% Load and return the hardware interface library for an OCT system.
%
%   INPUTS:
%       octSystemName: Name of the OCT system to load. 
%           Supported values: 'Ganymede', 'GAN632'. Keep empty if library
%           is already loaded.
%       skipHardware: When set to true, will skip hardware.
%       v: Verbose mode. Default is false.
%
%   OUTPUT:
%       octSystemModule - Handle or structure representing the loaded 
%                         hardware interface library.

%% Store module in a global varible 
persistent gOCTSystemModule;
persistent gOCTSystemName;
persistent gSkipHardware;

if ~isempty(gOCTSystemName)
    octSystemModule = gOCTSystemModule;
    octSystemName = gOCTSystemName;
    skipHardware = gSkipHardware;
    return;
end

%% Input checks
if ~exist('octSystemName','var') || isempty('octSystemName')
    error("yOCTLoadHardwareLib must be called with a valid 'octSystemName' the first time it is executed.");
end

if ~exist('skipHardware','var')
    skipHardware = false;
end

if ~exist('v','var')
    v = false;
end

validSystems = {'Ganymede', 'Gan632'};
if ~any(strcmpi(octSystemName, validSystems))
    error(['Invalid OCT System: %s' newline ...
           'Valid options are: ''Ganymede'' or ''Gan632'''], octSystemName);
end

%% Skip hardware path
if skipHardware
    gOCTSystemName = lower(octSystemName);
    gOCTSystemModule = [];
    gSkipHardware = true;

    % Return 
    octSystemModule = gOCTSystemModule;
    octSystemName = gOCTSystemName;
    skipHardware = gSkipHardware;
    return;
else
    gSkipHardware = false;
end

%% Initialize library based on system type
octSystemName = lower(octSystemName);

switch(octSystemName)
    case 'ganymede'
        % Ganymede: C# library 

        % Verify that library wasn't loaded before
        if ~isempty(which('ThorlabsImagerNET.ThorlabsImager')) 
            error('ThorlabsImagerNET loaded before, this should never happen.');
        end
    
        % Find the folder that c# dll is at.
        currentFileFolder = fileparts(mfilename('fullpath'));
	    libFolder = [currentFileFolder '\Lib\'];
	    
	    if ~exist([libFolder 'SpectralRadar.dll'],'file')
		    % Copy Subfolders to main lib folder
		    copyfile([libFolder 'LaserDiode\*.*'],libFolder,'f');
		    copyfile([libFolder 'MotorController\*.*'],libFolder,'f');
		    copyfile([libFolder 'ThorlabsOCT\*.*'],libFolder,'f');
	    end
        
        % Load Assembly
        asm = NET.addAssembly([libFolder 'ThorlabsImagerNET.dll']);
    
        % Mark assembly as loaded
        gOCTSystemModule = asm; 
        
    case 'gan632'
        % Gan632: Python SDK (pyspectralradar)
        gOCTSystemModule = yOCTImportPythonModule(...
            'packageName', 'thorlabs_imager_oct', ...
            'repoName', fullfile(fileparts(mfilename('fullpath')), 'ThorlabsImagerPython'), ...
            'v', v);
        
    otherwise
        error('This should never happen')
end

gOCTSystemName = lower(octSystemName);

%% Return 
octSystemModule = gOCTSystemModule;
octSystemName = gOCTSystemName;
skipHardware = gSkipHardware;
