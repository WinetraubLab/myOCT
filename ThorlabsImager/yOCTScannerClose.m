function yOCTScannerClose(v)
% Close OCT scanner (Ganymede only for now)
%
% INPUTS:
%   v: verbose mode, default: false

%% Input checks
if ~exist('v','var')
    v = false;
end

%% Close scanner
if (v)
    fprintf('%s Closing Scanner...\n', datestr(datetime));
end

ThorlabsImagerNET.ThorlabsImager.yOCTScannerClose();

if (v)
    fprintf('%s Scanner Closed\n', datestr(datetime));
end
end
