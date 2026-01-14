function isScannerInitialized = yOCTScannerStateGet()
% Get the current scanner initialization state (centralized state tracking)
% This function accesses the persistent scanner state managed by yOCTHardwareLibSetUp
%
% OUTPUT:
%   isScannerInitialized: boolean indicating if scanner is currently initialized

persistent gScannerIsInitialized;

if isempty(gScannerIsInitialized)
    isScannerInitialized = false;
else
    isScannerInitialized = gScannerIsInitialized;
end

end
