function yOCTScannerStateSet(isInitialized)
% Set the scanner initialization state.
% Delegates to yOCTHardwareState which holds the single persistent store.
%
% INPUT:
%   isInitialized: boolean indicating if scanner is initialized (true) or closed (false)

yOCTHardwareState('set', 'scannerInitialized', logical(isInitialized));

end
