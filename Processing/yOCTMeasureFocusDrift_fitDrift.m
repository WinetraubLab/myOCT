function [focusPositionInImageZpix, fitDiagnostics] = yOCTMeasureFocusDrift_fitDrift( ...
    zClickedStage_mm, focusClicked_pix, zAllDepths_mm, zPixelSize_um, nZPixels, varargin)
% Fit a physically-constrained line to clicked focus positions and return a
% focus pixel for every z-depth in the scan. This is the math core of
% yOCTMeasureFocusDrift: it has no GUI, no files and no hardware, so it can
% be tested automatically (see test_yOCTMeasureFocusDrift_fitDrift).
%
% WHY A LINE, AND WHY THE SLOPE IS BOUNDED (the physics):
%   Between tiles the stage moves the sample up by s. With an immersion
%   medium of index ni (water, 1.33) and tissue of index ns, paraxial Snell
%   refraction puts the focus at geometric depth s*ns/ni below the
%   tissue interface, and the OCT image displays optical path length divided
%   by the reconstruction index na (see yOCTInterfToScanCpx_getZ). Combining
%   the two, the focus pixel is LINEAR in stage z with slope
%       m = (ns^2 - ni^2) / (ni * na)    [um in image / um of stage]
%   Tissue never has an index below water, so ns >= ni and therefore m >= 0:
%   as the stage goes deeper the focus can only stay put or move deeper in
%   the image, never up. Cleared tissue tops out around ns ~ 1.55, so m is
%   bounded above as well. In contrast, any FIXED structure (coverslip,
%   fiber, bright nucleus) moves in the image with slope -ni/na
%   (~ -0.89..-0.95 um/um depending on na): opposite direction and
%   typically 3..5x larger in magnitude (more for weakly cleared tissue).
%   A click on a structure instead of on the focus therefore shows up as a large
%   negative-going outlier, which the robust fit + physical bounds below are
%   designed to identify and reject.
%
%   For stage z <= 0 the focus sits in the immersion medium above the
%   tissue, where there is no index mismatch and hence no drift, so the
%   fitted line is held flat at its z = 0 value (hinge at z = 0).
%
% INPUTS:
%   zClickedStage_mm - stage z position of each accepted click [mm]
%   focusClicked_pix - clicked focus pixel for each click (1-based)
%   zAllDepths_mm    - z-depths at which to evaluate the fit, usually the
%                      zDepths list of ScanInfo.json [mm]
%   zPixelSize_um    - size of one image z pixel [um in medium]
%   nZPixels         - number of z pixels in one tile image
%
% OPTIONAL NAME-VALUE PAIRS:
%   Parameter                   Default  Notes
%   tissueRefractiveIndex       1.4      na used by the reconstruction
%   immersionRefractiveIndex    1.33     ni between objective and sample
%   maxTissueRefractiveIndex    1.55     largest plausible ns (slope cap)
%   v                           false    print a human-readable summary
%
% OUTPUTS:
%   focusPositionInImageZpix - 1 x length(zAllDepths_mm) rounded focus pixel
%       for every depth. Guaranteed inside [1, nZPixels] and non-decreasing.
%   fitDiagnostics - struct with fields:
%       slopeMeasured_pixPerUm - robust slope before physical clamping
%       slopeUsed_pixPerUm     - slope actually used (after clamping)
%       slope_umPerUm          - slopeUsed in um(image)/um(stage)
%       intercept_pix          - fitted focus pixel at stage z = 0
%       impliedTissueN         - ns implied by the measured slope. Equals ni
%                                when the slope is zero within noise; NaN
%                                only when the slope is so negative that
%                                clicks must have tracked a fixed structure
%       keptIdx, rejectedIdx   - indices into the input click list
%       rejectedReason         - cellstr, one reason per rejected click
%       wasSlopeClamped        - true if the slope hit a physical bound
%       driftRegime            - 'normal' | 'no-measurable-drift' |
%                                'clamped-to-max' | 'suspicious-structure-clicks'
%       seSlope_pixPerUm       - standard error of the measured slope
%       seAtDepth_pix          - 1 x nDepths standard error of the line
%       maxMeasuredZ_mm        - deepest accepted click
%       messages               - cellstr of summary/warning lines

%% Parse inputs
p = inputParser;
addRequired(p, 'zClickedStage_mm', @isnumeric);
addRequired(p, 'focusClicked_pix', @isnumeric);
addRequired(p, 'zAllDepths_mm', @isnumeric);
addRequired(p, 'zPixelSize_um', @(x)(isnumeric(x) && isscalar(x) && x > 0));
addRequired(p, 'nZPixels', @(x)(isnumeric(x) && isscalar(x) && x >= 1));
addParameter(p, 'tissueRefractiveIndex', 1.4, @(x)(isnumeric(x) && isscalar(x) && x >= 1));
addParameter(p, 'immersionRefractiveIndex', 1.33, @(x)(isnumeric(x) && isscalar(x) && x >= 1));
addParameter(p, 'maxTissueRefractiveIndex', 1.55, @(x)(isnumeric(x) && isscalar(x) && x >= 1));
addParameter(p, 'v', false, @islogical);
parse(p, zClickedStage_mm, focusClicked_pix, zAllDepths_mm, zPixelSize_um, nZPixels, varargin{:});
in = p.Results;

na = in.tissueRefractiveIndex;
ni = in.immersionRefractiveIndex;
nsMax = in.maxTissueRefractiveIndex;
dz_um = in.zPixelSize_um;
nZ = round(in.nZPixels);

% Rejection constants. A genuine click error is a few pixels; a click on a
% fixed structure diverges from the focus at ~(m + ni/na)/dz pixels per um
% of stage (~0.8 pix/um typically), i.e. ~40 pixels per 50 um measured step.
% The floor sits well below that but above ~3 sigma of honest click noise,
% so noisy-but-genuine clicks are never rejected (rejecting them would also
% make the residual-based uncertainty estimate collapse).
REJECT_FLOOR_PIX = 15;
MAX_REJECT_ITERATIONS = 6;

msgs = {};

%% Clean input clicks
zClicked_um = zClickedStage_mm(:) * 1e3;   % stage position in um
pixClicked = focusClicked_pix(:);

badInput = isnan(zClicked_um) | isnan(pixClicked);
if any(badInput)
    msgs{end+1} = sprintf('%d click(s) had NaN values and were ignored.', sum(badInput));
end
% Clicks at z <= 0 are in the immersion medium regime (no drift) and would
% bias the tissue slope; the protocol measures from inside the tissue only.
inGel = zClicked_um < 0 & ~badInput;
if any(inGel)
    msgs{end+1} = sprintf(['%d click(s) at stage z < 0 were ignored: above the tissue ' ...
        'the focus does not drift, so they do not inform the tissue slope.'], sum(inGel));
end
useI = find(~badInput & ~inGel);
z = zClicked_um(useI);
pix = pixClicked(useI);
n = numel(z);

if n == 0
    error('yOCTMeasureFocusDrift:noClicks', ...
        'No usable focus measurements were provided. The focus was not visible/clickable on any tile.');
end

%% Robust fit (Theil-Sen) with iterative physical outlier rejection
% Physical slope bounds in pix/um of stage:
mMin_pixUm = 0;
mMax_pixUm = (nsMax^2 - ni^2) / (ni * na) / dz_um;

keptLocal = (1:n)';           % indices into z/pix
rejectedLocal = zeros(0, 1);
rejectedResidual = zeros(0, 1);

if n == 1
    slopeMeasured = 0;
    intercept = pix(1);
    msgs{end+1} = 'Only one focus click: assuming no drift (constant focus).';
else
    % The "+1" guarantees one final fit AFTER the last rejection, so the
    % returned slope/intercept are always computed on exactly keptLocal.
    for iter = 1:(MAX_REJECT_ITERATIONS + 1)
        [slopeMeasured, intercept, hasSlope] = theilSenFit(z(keptLocal), pix(keptLocal));
        if ~hasSlope
            % All kept clicks share the same stage z: no slope information.
            slopeMeasured = 0;
            intercept = median(pix(keptLocal));
            msgs{end+1} = 'All clicks are at the same stage z: assuming no drift (constant focus).'; %#ok<AGROW>
            break;
        end

        if numel(keptLocal) < 3 || iter > MAX_REJECT_ITERATIONS
            break; % Too few points to call any of them an outlier / done rejecting
        end

        % Residual-based rejection with a robust (MAD) scale estimate
        r = pix(keptLocal) - (slopeMeasured * z(keptLocal) + intercept);
        sigmaMad = 1.4826 * median(abs(r - median(r)));
        threshold = max(3 * sigmaMad, REJECT_FLOOR_PIX);
        isOut = abs(r) > threshold;
        if ~any(isOut)
            break;
        end
        rejectedLocal = [rejectedLocal; keptLocal(isOut)]; %#ok<AGROW>
        rejectedResidual = [rejectedResidual; r(isOut)];   %#ok<AGROW>
        keptLocal = keptLocal(~isOut);
    end
end

%% Uncertainty of the measured slope (needed to judge a negative slope)
% A true drift of ~0 (index-matched sample, weakly cleared tissue, or a
% simulated volume) measures as 0 +/- noise, so the slope comes out slightly
% negative in about half of all runs. That is NOT a sign of bad clicks; only
% a slope significantly below zero is.
nKept = numel(keptLocal);
if nKept >= 3
    rMeasured = pix(keptLocal) - (slopeMeasured * z(keptLocal) + intercept);
    sigmaResMeasured = sqrt(sum(rMeasured.^2) / (nKept - 2));
    SxxKept = sum((z(keptLocal) - mean(z(keptLocal))).^2);
    if SxxKept > 0
        % 0.91 = Theil-Sen asymptotic efficiency vs least squares
        seSlope_pixPerUm = sigmaResMeasured / sqrt(0.91 * SxxKept);
    else
        seSlope_pixPerUm = NaN;
    end
else
    seSlope_pixPerUm = NaN;
end

%% Clamp the slope to the physically possible range
slopeUsed = min(max(slopeMeasured, mMin_pixUm), mMax_pixUm);
wasSlopeClamped = (slopeUsed ~= slopeMeasured);

% Classify the result, so that noise around zero drift is never mistaken for
% bad clicks. Blaming the clicks requires the slope to be BOTH statistically
% below zero AND physically large enough to look like structure tracking,
% which sits at -ni/na. Clicks on a structure land at 10x this floor, so no
% alarm power is lost; a merely noisy zero no longer triggers it.
structureFloor_pixPerUm = 0.1 * (ni / na) / dz_um;
if isnan(seSlope_pixPerUm) || seSlope_pixPerUm <= 0
    slopeSigmas = NaN;  % fewer than 3 clicks: no statistics, physics decides
    isStructureLike = slopeMeasured < -0.5 * (ni / na) / dz_um;
else
    slopeSigmas = slopeMeasured / seSlope_pixPerUm;
    isStructureLike = slopeSigmas < -3 && slopeMeasured < -structureFloor_pixPerUm;
end

if isStructureLike
    driftRegime = 'suspicious-structure-clicks';
elseif abs(slopeSigmas) < 2
    driftRegime = 'no-measurable-drift';
elseif wasSlopeClamped && slopeMeasured > 0
    driftRegime = 'clamped-to-max';
else
    driftRegime = 'normal';
end

if wasSlopeClamped
    % Re-anchor the intercept so the clamped line still passes through the data
    intercept = median(pix(keptLocal) - slopeUsed * z(keptLocal));
end
switch driftRegime
    case 'suspicious-structure-clicks'
        msgs{end+1} = sprintf(['Measured drift slope (%.3f um/um) is significantly negative, which is ' ...
            'not physical (tissue index cannot be below the immersion medium). Clamped to 0, but ' ...
            'REVIEW THE MEASUREMENT: negative apparent drift means clicks landed on a fixed structure ' ...
            '(e.g. coverslip) instead of the focus.'], slopeMeasured * dz_um);
    case 'no-measurable-drift'
        if slopeMeasured < 0 % only worth a note when we actually clamped
            msgs{end+1} = sprintf(['No measurable focus drift: slope %.3f um/um is zero within ' ...
                'noise (%.1f sigma). Using a constant focus, which is the correct answer for an ' ...
                'index-matched or weakly mismatched sample.'], ...
                slopeMeasured * dz_um, abs(slopeSigmas));
        end
    case 'clamped-to-max'
        msgs{end+1} = sprintf(['Measured drift slope (%.3f um/um) exceeds the physical maximum for ' ...
            'tissue index %.2f. Clamped to %.3f um/um.'], ...
            slopeMeasured * dz_um, nsMax, mMax_pixUm * dz_um);
end

% Tissue index implied by the measured slope, floored at the immersion index
% for the same reason the slope is floored at zero: tissue is never lighter
% than water. NaN is reserved for slopes so negative that no index explains
% them, i.e. clicks that tracked a fixed structure.
nsSquared = ni^2 + (slopeMeasured * dz_um) * ni * na;
if strcmp(driftRegime, 'suspicious-structure-clicks')
    impliedTissueN = NaN;
else
    impliedTissueN = sqrt(max(nsSquared, ni^2));
end

%% Reasons for the rejected clicks (for the user, in physical terms)
rejectedReason = cell(numel(rejectedLocal), 1);
for k = 1:numel(rejectedLocal)
    if rejectedResidual(k) < 0
        rejectedReason{k} = sprintf(['click at z=%.3f mm is %.0f pixels above the drift line: ' ...
            'consistent with a click on a fixed structure (coverslip/tissue feature), ' ...
            'which moves opposite to the focus.'], ...
            z(rejectedLocal(k)) * 1e-3, abs(rejectedResidual(k)));
    else
        rejectedReason{k} = sprintf('click at z=%.3f mm is %.0f pixels below the drift line (outlier).', ...
            z(rejectedLocal(k)) * 1e-3, rejectedResidual(k));
    end
    msgs{end+1} = sprintf('Rejected %s', rejectedReason{k}); %#ok<AGROW>
end

%% Evaluate the line at every requested depth (hinge at z = 0)
zAll_um = zAllDepths_mm(:)' * 1e3;
zEffective_um = max(zAll_um, 0);    % no drift while the focus is in the immersion medium
focusLine = slopeUsed * zEffective_um + intercept;
focusPositionInImageZpix = round(focusLine);

% Belt and suspenders: the construction above cannot leave [1, nZ] when the
% clicks themselves are inside the image, but clamp anyway.
outOfRange = focusPositionInImageZpix < 1 | focusPositionInImageZpix > nZ;
if any(outOfRange)
    msgs{end+1} = sprintf(['%d depth(s) had their focus clamped to the image boundary. ' ...
        'The focus is not usable there; consider not scanning that deep.'], sum(outOfRange));
end
focusPositionInImageZpix = min(max(focusPositionInImageZpix, 1), nZ);

%% Uncertainty of the fitted line at each depth
% Standard error of the fitted line, with two corrections that keep it
% honest for this estimator (verified by the coverage test in
% test_yOCTMeasureFocusDrift_fitDrift): the intercept is a median, whose
% variance is pi/2 times that of a mean, and the Theil-Sen slope has ~0.91
% asymptotic efficiency vs least squares for Gaussian click noise.
if nKept >= 3
    rKept = pix(keptLocal) - (slopeUsed * z(keptLocal) + intercept);
    sigmaRes = sqrt(sum(rKept.^2) / (nKept - 2));
    zBar = mean(z(keptLocal));
    Sxx = sum((z(keptLocal) - zBar).^2);
    if Sxx > 0
        seAtDepth_pix = sigmaRes * sqrt((pi/2)/nKept + ((zEffective_um - zBar).^2) / (0.91 * Sxx));
    else
        seAtDepth_pix = sigmaRes * sqrt(pi/2) * ones(size(zEffective_um)) / sqrt(nKept);
    end
else
    seAtDepth_pix = nan(size(zEffective_um));
end

%% Extrapolation coverage warning
maxMeasuredZ_mm = max(z(keptLocal)) * 1e-3; % deepest click that survived rejection
maxRequestedZ_mm = max(zAllDepths_mm(:));
if maxRequestedZ_mm - maxMeasuredZ_mm > 0.1 % more than 100 um extrapolated
    [~, deepestI] = max(zAll_um);
    msgs{end+1} = sprintf(['Focus measured down to z=%.2f mm but the scan reaches z=%.2f mm: ' ...
        'below %.2f mm the focus position is an extrapolation ' ...
        '(estimated error at the deepest tile: +/-%.0f pixels). ' ...
        'Measure as deep as the focus is visible to reduce this.'], ...
        maxMeasuredZ_mm, maxRequestedZ_mm, maxMeasuredZ_mm, 2 * seAtDepth_pix(deepestI));
end

%% Package diagnostics
fitDiagnostics = struct();
fitDiagnostics.slopeMeasured_pixPerUm = slopeMeasured;
fitDiagnostics.slopeUsed_pixPerUm = slopeUsed;
fitDiagnostics.slope_umPerUm = slopeUsed * dz_um;
fitDiagnostics.intercept_pix = intercept;
fitDiagnostics.impliedTissueN = impliedTissueN;
fitDiagnostics.keptIdx = useI(keptLocal);
fitDiagnostics.rejectedIdx = useI(rejectedLocal);
fitDiagnostics.rejectedReason = rejectedReason;
fitDiagnostics.wasSlopeClamped = wasSlopeClamped;
fitDiagnostics.driftRegime = driftRegime;
fitDiagnostics.seSlope_pixPerUm = seSlope_pixPerUm;
fitDiagnostics.seAtDepth_pix = seAtDepth_pix;
fitDiagnostics.maxMeasuredZ_mm = maxMeasuredZ_mm;
fitDiagnostics.zPixelSize_um = dz_um;
fitDiagnostics.messages = msgs;

if in.v
    fprintf('Focus drift fit: slope = %.3f um/um (%.1f pix/mm)', ...
        fitDiagnostics.slope_umPerUm, slopeUsed * 1e3);
    if ~isnan(impliedTissueN)
        fprintf(', implied tissue n = %.3f', impliedTissueN);
    end
    fprintf('. Kept %d of %d clicks.\n', nKept, n);
    for k = 1:numel(msgs)
        fprintf('  - %s\n', msgs{k});
    end
end

end


function [slope, intercept, hasSlope] = theilSenFit(z_um, pix)
% Theil-Sen robust line fit: the slope is the median of all pairwise slopes
% and the intercept the median of (pix - slope*z). Unlike least squares, a
% minority of wrong clicks cannot drag the answer: k bad clicks out of n
% contaminate only the pairs that touch them, and as long as those are under
% half of all pairs the median lands on a clean pair. All pairs vote
% (not just long-baseline ones) precisely because bad clicks cluster at the
% ends of the measured range - where the focus is hardest to see - and a
% long-baseline-only vote would let those endpoints touch most ballots.
nPts = numel(z_um);
[jj, ii] = meshgrid(1:nPts, 1:nPts);
isPair = jj(:) > ii(:);                       % each unordered pair once
dzPair = z_um(jj(:)) - z_um(ii(:));
valid = isPair & abs(dzPair) > 1e-9;          % pairs at distinct stage z

if ~any(valid)
    slope = NaN; intercept = NaN; hasSlope = false;
    return;
end

pairSlopes = (pix(jj(valid)) - pix(ii(valid))) ./ dzPair(valid);
slope = median(pairSlopes);
intercept = median(pix - slope * z_um);
hasSlope = true;
end
