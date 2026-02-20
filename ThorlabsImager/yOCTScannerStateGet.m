function isScannerInitialized = yOCTScannerStateGet()
% Get the current scanner initialization state.
% Delegates to yOCTScannerState which holds the single persistent variable.
%
% OUTPUT:
%   isScannerInitialized: boolean indicating if scanner is currently initialized

isScannerInitialized = yOCTScannerState();

end
