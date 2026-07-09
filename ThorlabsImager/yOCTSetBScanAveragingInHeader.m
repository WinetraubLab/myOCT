function yOCTSetBScanAveragingInHeader(tileFolder, nBScanAvg)
% Record Bscan averaging count in a ThorImageOCT Header.xml 
% so MATLAB averages the repeats on load
%
% INPUTS:
%   tileFolder - folder that contains Header.xml (a single tile like Data01)
%   nBScanAvg  - number of averaged Bscans per Y position

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
% current integer value so the function is re-runnable
newTxt = regexprep(txt, '<SlowAxis>\s*\d+\s*</SlowAxis>', ...
    sprintf('<SlowAxis>%d</SlowAxis>', nBScanAvg), 'once');

if strcmp(newTxt, txt)
    if ~isempty(regexp(txt, sprintf('<SlowAxis>\\s*%d\\s*</SlowAxis>', nBScanAvg), 'once'))
        % Already set to the requested value: nothing to do.
        return;
    end
    warning(['yOCTSetBScanAveragingInHeader: no <SlowAxis> tag found in "%s"; ' ...
        'header left unchanged.'], headerPath);
    return;
end

% Write back as raw bytes so the Windows paths/percent signs in the header are
% preserved verbatim (no fprintf escape interpretation):
fid = fopen(headerPath, 'w');
if fid < 0
    error('Could not open "%s" for writing.', headerPath);
end
fwrite(fid, newTxt, 'char');
fclose(fid);

end
