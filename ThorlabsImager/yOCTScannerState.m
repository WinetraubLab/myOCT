function isScannerInitialized = yOCTScannerState(newState)
% Central store for scanner initialization state.
% Uses a single persistent variable so all callers share the same state.
%
% USAGE:
%   state = yOCTScannerState()      — read current state
%   state = yOCTScannerState(true)  — set state to true, return it
%   state = yOCTScannerState(false) — set state to false, return it
%
% OUTPUT:
%   isScannerInitialized: boolean (false when unset)

persistent gScannerIsInitialized;

% Set new state if provided
if nargin == 1
    gScannerIsInitialized = logical(newState);
end

% Return current state (default false if never set)
if isempty(gScannerIsInitialized)
    isScannerInitialized = false;
else
    isScannerInitialized = gScannerIsInitialized;
end

end
