function out = yOCT2Tif_ConvertBitsData(in, c, isInputBits, maxbit)
% isInputBits - when set to true will convert bits -> data
%                           false     convert data -> bits

%% Input
c = sort(c);

if ~exist('maxbit','var') || isempty(maxbit)
    maxbit = 2^16-1;
end

%% Conversion
if isInputBits
    % Bits -> Data
    out = double(in-1)*(c(2)-c(1))/(maxbit-1)+c(1);
    out(in==0) = NaN;
else
    % Data -> Bits
    if maxbit <= 2^8-1
        out = uint8((squeeze(in)-c(1))/(c(2)-c(1))*(maxbit-1))+1;
    else
        out = uint16((squeeze(in)-c(1))/(c(2)-c(1))*(maxbit-1))+1;
    end
    out(isnan(in)) = 0; %NaN is reserved for 0
end
