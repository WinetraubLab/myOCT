function st = yOCTReadProbeIniToStruct(probeIniPath)
% This function reads probe ini and returns a struct with all the
% information in it to be used later

%% Get the text in the probe ini
txt = fileread(probeIniPath);
txtlines = strsplit(txt,'\n');
txtlines = cellfun(@strtrim,txtlines,'UniformOutput',false);
txtlines(cellfun(@isempty,txtlines)) = [];

%% Loop over every line, evalue the input
st = struct();
for i=1:length(txtlines)
    ln = txtlines{i};
    
    %Remove comments and make line pretty
    if (contains(ln,'#'))
        %There is a comment in this line, remove it
        ln = ln(1:(find(ln=='#',1,'first')-1));
    end
    ln = strtrim(ln);
    if (isempty(ln))
        continue; %Nothing to do here
    end
    
    evalc(['st.' ln]);
end

% Ensure st.Oct2StageXYAngleDegue is valid
if ~isfield(st, 'Oct2StageXYAngleDeg')
    st.Oct2StageXYAngleDeg = 0; % default to 0 degrees if no value provided by user
else
    % User value must be a finite numeric scalar
    if ~isnumeric(st.Oct2StageXYAngleDeg) || ~isscalar(st.Oct2StageXYAngleDeg) || ~isfinite(st.Oct2StageXYAngleDeg)
        error('Oct2StageXYAngleDeg in octProbe INI file is invalid. Current value: %s\nINI file: %s', ...
              mat2str(st.Oct2StageXYAngleDeg), probeIniPath);
    end
    % User value must be within -180 and 180 degrees
    if st.Oct2StageXYAngleDeg < -180 || st.Oct2StageXYAngleDeg > 180
        error('Oct2StageXYAngleDeg out of range: expected [-180, 180] degrees. \nCurrent angle: %.6g\nINI file: %s', ...
              st.Oct2StageXYAngleDeg, probeIniPath);
    end
end
