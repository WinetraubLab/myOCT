function out = yOCT2Tif_ConvertBitsData(in, c, isInputBits, bitsPerSample)
% isInputBits - when set to true will convert bits -> data
%                           false     convert data -> bits

%% Input
c = sort(c);

if ~exist('bitsPerSample','var') || isempty(bitsPerSample)
    bitsPerSample = 16;
end

if bitsPerSample <= 8
    outputClass = 'uint8';
elseif bitsPerSample <= 16
    outputClass = 'uint16';
else
    error('yOCT2Tif_ConvertBitsData:UnsupportedBits', ...
        'bitsPerSample > 16 is not supported.');
end

maxValue = 2^bitsPerSample-1;

%% Conversion
if isInputBits
    % Bits -> Data
    out = double(in-1)*(c(2)-c(1))/(maxValue-1)+c(1);
    out(in==0) = NaN;
else
    % Data -> Bits
    out = feval(outputClass, (squeeze(in)-c(1))/(c(2)-c(1))*(maxValue-1)) + 1;
    out(isnan(in)) = 0; %NaN is reserved for 0
end
