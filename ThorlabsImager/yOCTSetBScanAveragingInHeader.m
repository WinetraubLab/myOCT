function yOCTSetBScanAveragingInHeader(tileFolder, nBScanAvg)
% YOCTSETBSCANAVERAGINGINHEADER  Record the B-scan averaging count in a
% ThorImageOCT Header.xml so MATLAB averages the repeats on load.
%
% WHY THIS EXISTS:
%   On Ganymede, the native DLL (ThorlabsImagerOCT.cpp) DOES acquire and save
%   B-scan averaging correctly: with nBScanAvg averages it writes
%   nYPixels * nBScanAvg separate Spectral{i}.data files (one B-scan each),
%   grouped nBScanAvg per Y position, Y-major - exactly the layout MATLAB's
%   reader expects (fileIndex = (y-1)*nBScanAvg + (avg-1)). However its native
%   metadata writer leaves Acquisition/SpeckleAveraging/SlowAxis = 1, so
%   yOCTLoadInterfFromFile_ThorlabsHeader thinks there is no averaging and
%   loads only the first frame of each Y position (ignoring the rest).
%
%   This function rewrites SlowAxis to nBScanAvg. The data files are already
%   correct, so no other change is needed. (Gan632's Python SDK already writes
%   SlowAxis correctly, so this is only needed for the native Ganymede path.)
%
% USAGE:
%   yOCTSetBScanAveragingInHeader(tileFolder, nBScanAvg)
%
% INPUTS:
%   tileFolder - folder that contains Header.xml (a single tile, e.g. Data01)
%   nBScanAvg  - number of averaged B-scans per Y position (>= 1)

if nBScanAvg < 1 || mod(nBScanAvg,1) ~= 0
    error('nBScanAvg must be a positive integer, got %g.', nBScanAvg);
end

headerPath = awsModifyPathForCompetability([tileFolder '/Header.xml']);
if ~exist(headerPath, 'file')
    warning('yOCTSetBScanAveragingInHeader: no Header.xml at "%s"; skipping.', tileFolder);
    return;
end

txt = fileread(headerPath);

% Rewrite the (single) SlowAxis element inside SpeckleAveraging. Match any
% current integer value so the function is idempotent / re-runnable.
newTxt = regexprep(txt, '<SlowAxis>\s*\d+\s*</SlowAxis>', ...
    sprintf('<SlowAxis>%d</SlowAxis>', nBScanAvg), 'once');

if strcmp(newTxt, txt)
    if ~isempty(regexp(txt, sprintf('<SlowAxis>\\s*%d\\s*</SlowAxis>', nBScanAvg), 'once'))
        % Already set to the requested value - nothing to do.
        return;
    end
    warning(['yOCTSetBScanAveragingInHeader: no <SlowAxis> tag found in "%s"; ' ...
        'header left unchanged.'], headerPath);
    return;
end

% Write back as raw bytes so the Windows paths/percent signs in the header are
% preserved verbatim (no fprintf escape interpretation).
fid = fopen(headerPath, 'w');
if fid < 0
    error('Could not open "%s" for writing.', headerPath);
end
fwrite(fid, newTxt, 'char');
fclose(fid);

end
