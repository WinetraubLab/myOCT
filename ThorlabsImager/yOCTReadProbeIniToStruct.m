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

% If Oct2StageXYAngleDeg is missing or invalid, set it to 0 degrees
if ~isfield(st,'Oct2StageXYAngleDeg') || ~isnumeric(st.Oct2StageXYAngleDeg) || ~isscalar(st.Oct2StageXYAngleDeg) || ~isfinite(st.Oct2StageXYAngleDeg)
    st.Oct2StageXYAngleDeg = 0;
end
