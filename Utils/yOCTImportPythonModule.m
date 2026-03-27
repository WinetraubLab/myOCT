function mod = yOCTImportPythonModule(varargin)
% yOCTImportPythonModule imports Python modules into MATLAB
%
% This function imports Python modules into MATLAB. It automatically:
%   1. Checks Python 3.11+ (64-bit) is configured in MATLAB
%   2. Adds required repository paths to Python's search path (sys.path)
%   3. Imports the Python module the user wants to use
%   4. Auto-installs missing necessasry Python packages
%   5. Returns ready-to-use module handle for calling functions
%
% Inputs:
%   'packageName'  - Python module to import (required)
%                    Example: 'database_library.log_scan_operations'
%   'repoName'     - Repository folder name (default: '' = current folder)
%                    Example: 'collect-virtual-histology-samples'
%   'v'            - Show verbose output messages (default: false)
%
% Output:
%   mod - Python module handle ready for use in MATLAB (e.g., mod.function_name())
%
% Usage example:
%   mod = yOCTImportPythonModule( ...
%       'packageName','database_library.log_scan_operations', ...
%       'repoName','collect-virtual-histology-samples', ...
%       'v',true);

% Parse inputs
p = inputParser;
addParameter(p,'packageName',[],@(s) ischar(s) || (isstring(s) && strlength(s)>0));
addParameter(p,'repoName','',@(s) ischar(s) || isstring(s));
addParameter(p,'v',false,@islogical);
parse(p,varargin{:});
in = p.Results;

if isempty(in.packageName)
    error('yOCTImportPythonModule:MissingPackage', ...
        'Provide ''packageName'', e.g. ''database_library.log_scan_operations''.');
end

% Check MATLAB's Python (require 3.11 or higher, 64-bit)
pe = pyenv;
if in.v
    fprintf('[Bridge] MATLAB Python: \nVersion = %s  \nExecutable=%s  Status=%s\n', ...
        char(string(pe.Version)), char(string(pe.Executable)), char(string(pe.Status)));
end
if strlength(string(pe.Executable))==0
    error(['MATLAB has no Python configured. Install 64-bit Python 3.11+ and then set pyenv:' newline ...
           '  pyenv("Version","<path\\to\\python.exe>")' newline ...
           'Download here: https://www.python.org/downloads/']);
end

% Extract version numbers
versionStr = string(pe.Version);
if pe.Status ~= "NotLoaded"
    % Handle different version string formats (e.g., "3.11.9", "3.11.9 (main, ...)")
    versionOnly = extractBefore(versionStr + " ", " "); % Add space to handle cases without extra info
    versionParts = str2double(split(versionOnly, "."));
    
    % Ensure we have at least major and minor version numbers
    if length(versionParts) < 2 || any(isnan(versionParts(1:2)))
        error(['Could not get Python version: %s' newline ...
               'Expected format like "3.11.9" but got: %s'], ...
               char(versionOnly), char(versionStr));
    end
    
    majorVersion = versionParts(1);
    minorVersion = versionParts(2);
    
    % Require Python 3.11 or higher, but exclude Python 4.x for now
    if majorVersion < 3 || (majorVersion == 3 && minorVersion < 11) || majorVersion >= 4
        error(['MATLAB is using Python %s. Require Python 3.11 or higher (but not 4.x yet).' newline ...
               'Install compatible version and point MATLAB to it with pyenv("Version", ...).' newline ...
               'Download here: https://www.python.org/downloads/'], ...
               char(versionStr));
    end
end
pyexe = char(pe.Executable);

% Add repo (or pwd) to Python's sys.path; also try <repo>\src
if isempty(in.repoName)
    repoBase = pwd;
else
    % Check if repoName is already an absolute path
    if isfolder(char(in.repoName))
        % It's an absolute path, use it directly
        repoBase = char(in.repoName);
    else
        % It's a relative name, append to pwd
        repoBase = fullfile(pwd, char(in.repoName));
    end
end
candidates = string({repoBase, fullfile(repoBase,'src')});
parts  = split(string(in.packageName), '.');   % top-level package name
topPkg = parts(1);

% Get sys.path safely (import 'sys' first)
pysys  = py.importlib.import_module('sys'); % ensure we have sys
pypath = pysys.path;                        % this is a Python list

% List of current entries (as MATLAB strings) to avoid duplicates
existing = string(cellfun(@char, cell(py.list(pypath)), 'UniformOutput', false));

added = false;
for c = candidates
    % Check if package exists as folder OR as .py file
    if isfolder(fullfile(char(c), char(topPkg))) || isfile(fullfile(char(c), char(topPkg) + ".py"))
        if ~any(existing == c)
            if in.v, fprintf('[Bridge] Adding to sys.path: %s\n', char(c)); end
            % Call the Python list.insert(...) method
            pypath.insert(int32(0), c);
            existing = [c existing];
        end
        added = true;
    end
end
py.importlib.invalidate_caches();

if ~added && in.v
    fprintf('[Bridge] Warning: Could not find folder "%s" under: %s or %s\n', ...
        char(topPkg), char(candidates(1)), char(candidates(2)));
    fprintf('[Bridge] Proceeding anyway (package may already be on sys.path)...\n');
end

% Import with auto-install of missing dependencies
maxRetries = 4; % Set maximum retry attempts for installing missing packages
tried = string.empty;
for attempt = 1:maxRetries
    try
        py.importlib.invalidate_caches();
        
        % Reload if module is already loaded to ensure fresh code
        if py.bool(py.operator.contains(py.sys.modules, in.packageName))
            if in.v, fprintf('[Bridge] Module already loaded, reloading with latest changes: %s\n', char(in.packageName)); end
            sys_modules = py.sys.modules;
            existing_module = sys_modules{in.packageName};
            mod = py.importlib.reload(existing_module);
        else
            if in.v, fprintf('[Bridge] Loading module for first time: %s\n', char(in.packageName)); end
            mod = py.importlib.import_module(in.packageName);
        end
        
        if in.v, fprintf('[Bridge] Successfully imported module: %s\n', char(in.packageName)); end
        return
    catch ME
        msg = string(ME.message);
        token = regexp(msg, "No module named '([^']+)'", 'tokens', 'once');
        if isempty(token)
            % Escape any % characters in the error message to prevent formatting issues
            safeMsg = strrep(string(ME.message), '%', '%%');
            
            errMsg = sprintf(['Python import failed for package: %s\n' ...
                             'Error: %s\n' ...
                             'Hints:\n' ...
                             '  • Ensure the repo path (and/or its \\src) is on sys.path.\n' ...
                             '  • Verify the module name is correct: %s\n' ...
                             '  • Confirm MATLAB uses Python 3.11+ (64-bit): pyenv\n' ...
                             '  • If this is a dependency mismatch, install manually:\n' ...
                             '    "%s" -m pip install <package>'], ...
                             char(in.packageName), char(safeMsg), char(in.packageName), char(pyexe));
            
            error('yOCTImportPythonModule:ImportFailed', '%s', errMsg);
        end
        missing = string(token{1});
        if any(strcmpi(tried, missing))
            error('yOCTImportPythonModule:RepeatedMissing', ...
                  'Repeated missing module: %s. Aborting.', char(missing));
        end
        tried(end+1) = missing; %#ok<AGROW>
        if in.v, fprintf('[Bridge] Installing missing dependency: %s\n', char(missing)); end
        system(sprintf('"%s" -m pip install %s', pyexe, missing));
        % retry loop
    end
end

error('yOCTImportPythonModule:ExceededRetries', ...
      'Exceeded install/retry attempts while importing %s.', char(in.packageName));
end
