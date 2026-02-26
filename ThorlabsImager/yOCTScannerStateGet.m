function isScannerInitialized = yOCTScannerStateGet()
% Get the current scanner initialization state.
% Delegates to yOCTHardwareState which holds the single persistent store.
%
% OUTPUT:
%   isScannerInitialized: boolean indicating if scanner is currently initialized

isScannerInitialized = yOCTHardwareState('get', 'scannerInitialized');

end
