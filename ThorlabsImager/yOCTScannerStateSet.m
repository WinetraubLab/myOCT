function yOCTScannerStateSet(isInitialized)
% Set the scanner initialization state.
% Delegates to yOCTScannerState which holds the single persistent variable.
%
% INPUT:
%   isInitialized: boolean indicating if scanner is initialized (true) or closed (false)

yOCTScannerState(isInitialized);

end
