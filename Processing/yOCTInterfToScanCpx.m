function [scanCpx,dimensionsOut] = yOCTInterfToScanCpx (varargin)
% This function takes the interferogram loaded from yOCTLoadInterfFromFile
% and converts it to a complex scanCpx datastructure
%
% USAGE:
%       scanCpx = yOCTInterfToBScanCpx (interferogram,dimensions [,param1,value1,...])
% INPUTS
%   - interferogram - as loaded by yOCTLoadInterfFromFile. dimensions
%       should be (lambda,x,...)
%   - dimensions - Dimensions structure as loaded by yOCTLoadInterfFromFile.
%   - Optional Parameters
%       - 'dispersionQuadraticTerm', quadradic phase correction units of
%          [nm^2/rad]. Default value is 100[nm^2/rad], try increasing to
%          40*10^6 if the lens or system is not dispersion corrected.
%          try running Demo_DispersionCorrection, if unsure of the number
%          you need.
%          This number is sometimes reffered to as beta.
%       - 'band',[start end] - Use a Hann filter to filter out part of the
%          spectrum. Units are [nm]. Default is all spectrum
%       - 'interpMethod', see help yOCTEquispaceInterf for interpetation
%           methods
%		- 'n' - medium refractive index. default: 1.33
%               For brain tissue, use 1.35. Reference: Srinivasan VJ, Radhakrishnan H, Jiang JY, Barry S, & Cable AE (2012) Optical coherence microscopy for deep tissue imaging of the cerebral cortex with intrinsic contrast. Opt Express 20(3):2220-2239.
%		- 'peakOnly' - if set to true, only returns dimensions update. Default: false
%			dimensions = yOCTInterfToScanCpx (varargin)
% OUTPUT
%   scanCpx - 2D or 3D volume with dimensions (z,x,y). More if there is A/B
%       scan averaging, see yOCTLoadInterfFromFile for more information
%	dimensions - updated dimesions, adding dimesions for z
%
% Author: Yonatan W (Dec 27, 2017)

%% Hendle Inputs
if (iscell(varargin{1}))
    % the first varible contains a cell with the rest of the varibles, open it
    varargin = varargin{1};
end 

interferogram = varargin{1};
dimensionsIn = varargin{2};

% Optional Parameters
dispersionQuadraticTerm = 100; % Default Value
band = [];
interpMethod = []; % Default
n = 1.33;
peakOnly = false;
for i=3:2:length(varargin)
   eval([varargin{i} ' = varargin{i+1};']); % <-TBD - there should be a safer way
end

if (peakOnly)
	interferogram=interferogram(:,1,1,1,1,1); % In peak only mode only process one A Scan
end	

%% Check if interferogram is equispaced. If not, equispace it before processing
dimensions = yOCTChangeDimensionsStructureUnits(dimensionsIn,'nm');
lambda = dimensions.lambda.values;
k = 2*pi./(lambda); % Get wave lumber in [1/nm]

if (abs((max(diff(k)) - min(diff(k)))/max(k)) > 1e-10)
    % Not equispaced, equispacing needed
    [interferogram,dimensions] = yOCTEquispaceInterf(interferogram,dimensions,interpMethod);
    
    lambda = dimensions.lambda.values;
    k = 2*pi./(lambda); % Get wave lumber in [1/nm]
end
s = size(interferogram);

%% Filter bands
filter = zeros(size(k));
if ~isempty(band)
    % Provide a warning if band is out of lambda range
    if (band(1) < min(dimensions.lambda.values) || band(2) > max(dimensions.lambda.values))
        warning('Requested band is outside data borders, shrinking band size');
    end
    
    % Band filter to select sub band
    fLambda = linspace(band(1),band(2),length(dimensions.lambda.values));
    fVal = hann(length(fLambda)); 
    filter = interp1(fLambda,fVal,dimensions.lambda.values,'linear',0); %Extrapolation is 0 for values outside the filter
else
    % No band filter, so apply Hann filter on the entire sample
    filter = hann(length(filter));
end

% Normalize filter
filter = filter(:);
intensityNorm = sqrt(mean(filter.^2)); % This factor makes sure that filter energy doesn't go to infinity
filter = filter / intensityNorm; % Normalization

%% Reshape interferogram for easy parallelization
interf = reshape(interferogram,s(1),[]);

%% Dispersion & Overall filter

if exist('dispersionQuadraticTerm','var')
    % Apply quadratic term.
    dispersionPhase = -dispersionQuadraticTerm .* (k(:)-mean(k)).^2; %[rad]
    
    if exist('dispersionParameterA','var')
        warning('Both dispersionParameterA and dispersionQuadraticTerm are defined. Please notice that dispersionParameterA is depricated and will be ignored.');
    end
elseif exist('dispersionParameterA','var') 
    warning(['dispersionParameterA will be depriciated in favor of dispersionQuadraticTerm.' newline ...
        'To switch, apply dispersionQuadraticTerm = dispersionParameterA and see that image looks good it will shift up/down by ~30um']);
    
    %Technically dispersionPhase = -A*k^2. We added the term -A*(k-k0)^2
    %because when doing the ifft, ifft assumes that the first term is DC. which
    %in our case is not true. Thus by applying phase=-A*k^2 we introduce a
    %multiplicative phase term: A*k0^2 which does not effect the final result
    %however, if we run over A the phase term changes and in the fft world it
    %translates to translation that move our image up & down. To Avoid it we
    %subtract -A*(k-k0)^2
    dispersionPhase = -dispersionParameterA .* (k(:)-k(1)).^2; %[rad]
else
    error('Please define dispersionQuadraticTerm');
end

% Convert dispersion phase to a factor
dispersionComp = exp(1i*dispersionPhase);

%% Overall filter
filterAll = repmat(dispersionComp.*filter,[1 size(interf,2)]);

%% Generate Cpx 
ft = ifft((interf.*filterAll));
scanCpx = ft(1:(size(interf,1)/2),:);

%% Reshape back
scanCpx = reshape(scanCpx,[size(scanCpx,1) s(2:end)]);

%% Update Dimensions
dimensions.z.order = 1;
lambda = mean(dimensions.lambda.values)/1000; %[um]
dlambda = diff(dimensions.lambda.values([1 end]))/1000;%[um]
N = length(dimensions.lambda.values);
zStepSizeAir = 1/2*lambda^2/dlambda; %1/2 factor is because light goes back and forth
zStepSizeMedium = zStepSizeAir/n;
dimensions.z.values = linspace(0,zStepSizeMedium*N/2,N/2); 
dimensions.z.units = 'microns [in medium]';

dimensionsOut = dimensionsIn;
dimensionsOut.z = dimensions.z;

if (peakOnly)
	scanCpx = dimensionsOut;
end	