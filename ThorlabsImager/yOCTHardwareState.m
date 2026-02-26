function result = yOCTHardwareState(action, field, value)
% Central state store for all OCT hardware persistent variables.
% Single source of truth for hardware session state. All state lives in one
% persistent struct inside this function.
%
% INPUTS:
%   action - (required) Operation to perform. One of:
%       'get'      - Read a state field. Requires 'field'. Returns field value.
%       'set'      - Write a state field. Requires 'field' and 'value'. Returns value.
%       'reset'    - Clear all state back to defaults. No other inputs needed. Returns [].
%       'isLoaded' - Check if a system is loaded (systemName is not empty).
%                    No other inputs needed. Returns logical.
%
%   field - (required for 'get' and 'set') Name of the state field to read or write.
%       'systemModule'       - Handle or struct for the loaded hardware library
%       'systemName'         - Lowercase OCT system name: 'ganymede' or 'gan632'.
%       'skipHardware'       - Logical. true when running without real hardware.
%       'scannerInitialized' - Logical. true when the scanner is currently open.
%
%   value - (required for 'set' only) New value to assign to the specified field.
%
% OUTPUT:
%   result - Depends on action:
%       'get'      - Current value of the requested field.
%       'set'      - The value that was just written.
%       'reset'    - Empty ([]).
%       'isLoaded' - true if systemName is set, false otherwise.

persistent state;

% Initialize on first call
if isempty(state)
    state = defaultState();
end

switch lower(action)
    case 'reset'
        state = defaultState();
        result = [];

    case 'set'
        state.(field) = value;
        result = value;

    case 'get'
        result = state.(field);

    case 'isloaded'
        result = ~isempty(state.systemName);

    otherwise
        error('myOCT:yOCTHardwareState:badAction', ...
              'Unknown action ''%s''. Use ''get'', ''set'', ''reset'', or ''isLoaded''.', action);
end

end

% Helper
function s = defaultState()
    s = struct( ...
        'systemModule', [], ...
        'systemName',   [], ...
        'skipHardware', [], ...
        'scannerInitialized', false);
end
