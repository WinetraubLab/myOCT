function yOCTScannerStateSet(isInitialized)
% Set the scanner initialization state (centralized state tracking)
% This function modifies the persistent scanner state managed by yOCTHardwareLibSetUp
%
% INPUT:
%   isInitialized: boolean indicating if scanner is initialized (true) or closed (false)

persistent gScannerIsInitialized;

gScannerIsInitialized = isInitialized;

end
