classdef test_yOCTMeasureFocusDrift_fitDrift < matlab.unittest.TestCase
    % Automatic (no user interaction) tests for the focus drift fit math in
    % yOCTMeasureFocusDrift_fitDrift.
    %
    % The synthetic "truth" generator (truthFocusPix) derives the focus
    % position from the raw physics in two independent steps - paraxial
    % Snell refraction, then optical path length - and deliberately does NOT
    % use the closed-form slope (ns^2-ni^2)/(ni*na) that the estimator's
    % physical bounds are built on. If someone swaps ni and na in either
    % place, these tests catch it; a generator that reused the closed form
    % would only prove the code agrees with itself.
    %
    % Baseline physical scenario shared by many tests (matches the lab's
    % common configuration): water dipping objective (ni = 1.33), cleared
    % tissue (ns ~ 1.45), reconstruction index na = 1.5, z pixel 1.2713 um,
    % 1024 z pixels, focus at pixel 320 when it sits on the tissue interface.

    properties (Constant)
        NI = 1.33;          % immersion (water) refractive index
        NA = 1.5;           % reconstruction (display) refractive index
        DZ_UM = 1.2713;     % image z pixel size [um in medium]
        NZ = 1024;          % z pixels in one tile
        PIX0 = 320;         % focus pixel when focus is at the interface (z=0)
    end

    methods (Access = private)
        function pix = truthFocusPix(testCase, sStage_um, ns)
            % Ground-truth focus pixel vs stage depth, from first principles.
            % Step 1 (Snell, paraxial): moving the stage down by s puts the
            %   focus at geometric depth s*ns/ni below the interface.
            % Step 2 (OCT ranging): the image position is the optical path
            %   from a fixed reference: the water column shortens by s while
            %   the tissue column adds ns * (geometric depth). The display
            %   divides optical path by na.
            % For s <= 0 the focus is in the water where both media match:
            %   no drift.
            sEff = max(sStage_um, 0);
            dGeom_um = sEff .* (ns / testCase.NI);
            opl_um = -testCase.NI .* sEff + ns .* dGeom_um;
            pix = testCase.PIX0 + (opl_um ./ testCase.NA) ./ testCase.DZ_UM;
        end

        function pix = decoyStructurePix(testCase, sStage_um)
            % A fixed structure at the interface (e.g. coverslip reflection):
            % raising the sample by s shortens its optical path by ni*s, so
            % in the image it moves UP at ni/na um per um of stage.
            pix = testCase.PIX0 - (testCase.NI .* sStage_um ./ testCase.NA) ./ testCase.DZ_UM;
        end

        function [vec, diag] = runFit(testCase, zClicked_mm, clicks_pix, zAll_mm)
            [vec, diag] = yOCTMeasureFocusDrift_fitDrift( ...
                zClicked_mm, clicks_pix, zAll_mm, testCase.DZ_UM, testCase.NZ, ...
                'tissueRefractiveIndex', testCase.NA, ...
                'immersionRefractiveIndex', testCase.NI);
        end

        function verifyHardInvariants(testCase, vec, zAll_mm)
            % The guarantees yOCTProcessTiledScan relies on, valid for ANY input
            testCase.verifyEqual(numel(vec), numel(zAll_mm), ...
                'Output must have one focus value per requested depth');
            testCase.verifyTrue(all(isfinite(vec)), 'Focus vector must be finite');
            testCase.verifyTrue(all(vec >= 1 & vec <= testCase.NZ), ...
                'Focus vector must stay inside the image');
            testCase.verifyEqual(vec, round(vec), 'Focus vector must be integer pixels');
            [~, order] = sort(zAll_mm(:));
            vecSorted = vec(order);
            testCase.verifyTrue(all(diff(vecSorted) >= 0), ...
                'Focus must be non-decreasing with depth (slope >= 0 by physics)');
        end
    end

    methods (Test)
        function testExactRecoveryAcrossNs(testCase)
            % Noise-free clicks on the true line: the fit must recover the
            % implied tissue index and the focus at every depth, including
            % the extrapolated deep tiles and the hinged shallow tiles.
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            for ns = 1.33:0.02:1.53
                clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, ns));
                [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

                testCase.verifyHardInvariants(vec, zAll_mm);
                testCase.verifyEqual(diag.impliedTissueN, ns, 'AbsTol', 0.01, ...
                    sprintf('Implied tissue index should match truth (ns=%.2f)', ns));
                truthAll = testCase.truthFocusPix(zAll_mm * 1e3, ns);
                testCase.verifyLessThan(max(abs(vec - truthAll)), 4, ...
                    sprintf('Focus error vs truth too large (ns=%.2f)', ns));
                testCase.verifyEmpty(diag.rejectedIdx, ...
                    'No clicks should be rejected on clean data');
            end
        end

        function testMatchedIndexGivesFlatVector(testCase)
            % ns = ni: no index mismatch, no drift. The vector must be constant.
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, testCase.NI));
            [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

            testCase.verifyHardInvariants(vec, zAll_mm);
            testCase.verifyEqual(unique(vec), testCase.PIX0, ...
                'Matched-index scan must give a constant focus vector');
            testCase.verifyEqual(diag.slopeUsed_pixPerUm, 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(diag.impliedTissueN, testCase.NI, 'AbsTol', 0.01);
        end

        function testRegressionOverExtrapolationBug(testCase)
            % Reproduces the real July 2026 failure: a 125-depth scan to
            % z = 1.2 mm, focus clicked only down to z = 0.55 mm, and the
            % last two clicks accidentally on a fixed structure (once the
            % focus dims, the eye locks onto the brightest band). The old
            % interp1(...,'extrap') code extrapolated the corrupt final
            % segment linearly and produced NEGATIVE focus pixels, which
            % crashed yOCTProcessTiledScan inside its parfor loop.
            nsTruth = 1.45;
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, nsTruth));

            % Corrupt the deepest two clicks: from the last good focus they
            % track a fixed structure (decoy slope) instead of the focus
            lastGood = clicks(9); % z = 0.45 mm
            decoyDrop = @(ds_um) (testCase.NI * ds_um / testCase.NA) / testCase.DZ_UM;
            clicks(10) = round(lastGood - decoyDrop(50));   % z = 0.50 mm
            clicks(11) = round(lastGood - decoyDrop(100));  % z = 0.55 mm

            % Precondition: the OLD method must reproduce the crash scenario
            oldVec = round(interp1(zClicked_mm, clicks, zAll_mm, 'linear', 'extrap'));
            testCase.verifyTrue(any(oldVec < 1), ...
                'Precondition failed: old interp1 method should go out of the image on this data');

            % The new fit must survive it
            [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);
            testCase.verifyHardInvariants(vec, zAll_mm);

            % Both corrupt clicks identified
            testCase.verifyTrue(all(ismember([10 11], diag.rejectedIdx)), ...
                'The two structure-clicks must be rejected as outliers');

            % Slope and focus recovered from the 9 clean clicks
            slopeTruth_pixPerUm = ...
                (testCase.truthFocusPix(1000, nsTruth) - testCase.truthFocusPix(0, nsTruth)) / 1000;
            testCase.verifyEqual(diag.slopeUsed_pixPerUm, slopeTruth_pixPerUm, ...
                'RelTol', 0.15, 'Recovered drift slope too far from truth');
            truthAll = testCase.truthFocusPix(zAll_mm * 1e3, nsTruth);
            testCase.verifyLessThan(max(abs(vec - truthAll)), 5, ...
                'Focus vector should match truth everywhere, including extrapolated depths');

            % The user must be told most of the scan is extrapolated
            testCase.verifyTrue(any(contains(diag.messages, 'extrapolation')), ...
                'A warning about the unmeasured deep range must be issued');
        end

        function testCoverslipDecoyClicksRejected(testCase)
            % The other common mistake: the FIRST clicks (nearest the
            % coverslip) land on its bright reflection instead of the focus.
            nsTruth = 1.45;
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, nsTruth));
            clicks(1) = round(testCase.decoyStructurePix(50));
            clicks(2) = round(testCase.decoyStructurePix(100));

            [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);
            testCase.verifyHardInvariants(vec, zAll_mm);
            testCase.verifyTrue(all(ismember([1 2], diag.rejectedIdx)), ...
                'Clicks on the coverslip reflection must be rejected');

            slopeTruth_pixPerUm = ...
                (testCase.truthFocusPix(1000, nsTruth) - testCase.truthFocusPix(0, nsTruth)) / 1000;
            testCase.verifyEqual(diag.slopeUsed_pixPerUm, slopeTruth_pixPerUm, ...
                'RelTol', 0.15);
        end

        function testNoDriftWithNoiseIsNotAnError(testCase)
            % Regression for the "casi siempre sale error" complaint: when
            % the true drift is ~0 (index-matched sample, simulation, weakly
            % cleared tissue), the measured slope is 0 +/- noise and comes
            % out slightly negative in about half of all runs. That must be
            % reported as "no measurable drift" - a good, valid outcome -
            % and NEVER as "clicks landed on a structure".
            rng(11, 'twister');
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            truth = testCase.truthFocusPix(zClicked_mm * 1e3, testCase.NI); % flat
            sawNegativeSlope = false;
            for iter = 1:200
                clicks = round(truth + randn(size(truth)) * 5);
                [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

                testCase.verifyHardInvariants(vec, zAll_mm);
                testCase.verifyNotEqual(diag.driftRegime, 'suspicious-structure-clicks', ...
                    'Noise around zero drift must never be blamed on structure clicks');
                testCase.verifyFalse(isnan(diag.impliedTissueN), ...
                    'Zero-within-noise drift implies ns ~ ni, not "not physical"');
                sawNegativeSlope = sawNegativeSlope || diag.slopeMeasured_pixPerUm < 0;
            end
            testCase.verifyTrue(sawNegativeSlope, ...
                'Test should exercise the negative-measured-slope half of the distribution');
        end

        function testWeakButRealDriftIsNotCalledNoise(testCase)
            % The noise band must not swallow a small but genuine drift:
            % ns = 1.36 drifts only 0.04 um/um, yet over a 1.2 mm stack that
            % is ~38 pixels - four focusSigma, well worth correcting.
            rng(23, 'twister');
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            nsWeak = 1.36;
            truth = testCase.truthFocusPix(zClicked_mm * 1e3, nsWeak);
            clicks = round(truth + randn(size(truth)) * 5);
            [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

            testCase.verifyHardInvariants(vec, zAll_mm);
            testCase.verifyEqual(diag.driftRegime, 'normal', ...
                'A statistically significant drift must not be labelled "no measurable drift"');
            testCase.verifyEqual(diag.impliedTissueN, nsWeak, 'AbsTol', 0.03);
            truthAll = testCase.truthFocusPix(zAll_mm * 1e3, nsWeak);
            testCase.verifyLessThan(max(abs(vec - truthAll)), 12, ...
                'Weak drift must still be tracked, not flattened');
        end

        function testAllStructureClicksFlagged(testCase)
            % The opposite case must still alarm: every click tracking a
            % fixed structure (the July 2026 failure mode) gives a slope far
            % below anything noise can explain.
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.decoyStructurePix(zClicked_mm * 1e3));
            [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

            testCase.verifyHardInvariants(vec, zAll_mm);
            testCase.verifyEqual(diag.driftRegime, 'suspicious-structure-clicks');
            testCase.verifyTrue(isnan(diag.impliedTissueN));
            testCase.verifyEqual(diag.slopeUsed_pixPerUm, 0, 'AbsTol', 1e-12, ...
                'Structure-click slope must be clamped to zero, keeping the vector safe');
        end

        function testHingeBelowZero(testCase)
            % Above the tissue (z <= 0) the focus is in the immersion medium:
            % no mismatch, no drift. The vector must be flat there and only
            % start drifting for z > 0.
            zAll_mm = [-0.1 -0.05 0 0.5 1.0];
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, 1.5));
            vec = testCase.runFit(zClicked_mm, clicks, zAll_mm);

            testCase.verifyEqual(vec(1), vec(3), ...
                'Focus must not drift above the tissue (hinge at z = 0)');
            testCase.verifyEqual(vec(2), vec(3));
            testCase.verifyGreaterThan(vec(5), vec(3), ...
                'Focus must drift deeper inside the tissue (ns = 1.5)');
        end

        function testFuzzHardInvariants(testCase)
            % Whatever garbage the clicks contain - noise, decoy clicks,
            % few points - the output must ALWAYS be safe for
            % yOCTProcessTiledScan: finite, integer, inside the image,
            % non-decreasing. This is the "the July 2026 crash can never
            % happen again" test.
            rng(42, 'twister');
            zAll_mm = -0.05:0.01:1.2;
            for iter = 1:3000
                ns = 1.33 + rand() * 0.27;
                nClicks = randi([2 14]);
                zClicked_mm = sort(50 + rand(1, nClicks) * 550) * 1e-3;
                noiseSigma = rand() * 15;
                pixAtInterface = 150 + rand() * 550;

                truth = testCase.truthFocusPix(zClicked_mm * 1e3, ns) ...
                    - testCase.PIX0 + pixAtInterface;
                clicks = round(truth + randn(1, nClicks) * noiseSigma);

                % Replace a random subset with decoy structure clicks
                nBad = min(nClicks - 1, floor(rand() * 0.3 * nClicks));
                if nBad > 0
                    badI = randperm(nClicks, nBad);
                    clicks(badI) = round(testCase.decoyStructurePix(zClicked_mm(badI) * 1e3) ...
                        - testCase.PIX0 + pixAtInterface);
                end
                clicks = min(max(clicks, 1), testCase.NZ); % a GUI click is always inside the image

                vec = testCase.runFit(zClicked_mm, clicks, zAll_mm);
                testCase.verifyHardInvariants(vec, zAll_mm);
            end
        end

        function testUncertaintyIsHonest(testCase)
            % The reported standard error must (a) grow with extrapolation
            % distance and (b) actually cover the truth: over many noisy
            % realizations, the true focus at the deepest (fully
            % extrapolated) tile must fall within +/-2 se most of the time.
            rng(7, 'twister');
            nsTruth = 1.45;
            noiseSigma = 5;
            zAll_mm = [0.3 1.2];
            zClicked_mm = (50:50:550) * 1e-3;
            truthClicked = testCase.truthFocusPix(zClicked_mm * 1e3, nsTruth);
            truthDeep = testCase.truthFocusPix(1.2e3, nsTruth);

            nCovered = 0; nTrials = 800;
            for iter = 1:nTrials
                clicks = round(truthClicked + randn(size(truthClicked)) * noiseSigma);
                [vec, diag] = testCase.runFit(zClicked_mm, clicks, zAll_mm);

                testCase.verifyGreaterThan(diag.seAtDepth_pix(2), diag.seAtDepth_pix(1), ...
                    'Uncertainty must grow with extrapolation distance');
                if abs(vec(2) - truthDeep) <= 2 * diag.seAtDepth_pix(2) + 0.5 % 0.5 for rounding
                    nCovered = nCovered + 1;
                end
            end
            coverage = nCovered / nTrials;
            testCase.verifyGreaterThan(coverage, 0.88, ...
                sprintf('2-sigma coverage at the deepest tile is only %.1f%%: the reported uncertainty is overconfident', ...
                coverage * 100));
        end

        function testDegenerateInputs(testCase)
            zAll_mm = 0:0.01:0.5;

            % No clicks at all
            testCase.verifyError(@() yOCTMeasureFocusDrift_fitDrift( ...
                [], [], zAll_mm, testCase.DZ_UM, testCase.NZ), ...
                'yOCTMeasureFocusDrift:noClicks');

            % Only clicks above the tissue (z < 0) are dropped -> no clicks left
            testCase.verifyError(@() yOCTMeasureFocusDrift_fitDrift( ...
                [-0.05 -0.02], [300 310], zAll_mm, testCase.DZ_UM, testCase.NZ), ...
                'yOCTMeasureFocusDrift:noClicks');

            % A single click: constant focus
            vec = testCase.runFit(0.1, 400, zAll_mm);
            testCase.verifyEqual(unique(vec), 400);
            testCase.verifyHardInvariants(vec, zAll_mm);

            % Two clicks: a line through them (clamped to physics)
            vec = testCase.runFit([0.1 0.3], [400 410], zAll_mm);
            testCase.verifyHardInvariants(vec, zAll_mm);

            % All clicks at the same stage z: no slope information -> constant
            vec = testCase.runFit([0.2 0.2 0.2], [400 405 410], zAll_mm);
            testCase.verifyEqual(unique(vec), 405);

            % NaN clicks are ignored
            [vec, diag] = testCase.runFit([0.1 0.2 NaN], [400 405 NaN], zAll_mm);
            testCase.verifyHardInvariants(vec, zAll_mm);
            testCase.verifyEqual(numel(diag.keptIdx) + numel(diag.rejectedIdx), 2);
        end

        function testOutputContract(testCase)
            % Exactly what yOCTProcessTiledScan expects, on the lab's real
            % scan geometry (125 depths from -0.04 to 1.2 mm).
            zAll_mm = -0.04:0.01:1.2;
            zClicked_mm = (50:50:550) * 1e-3;
            clicks = round(testCase.truthFocusPix(zClicked_mm * 1e3, 1.45));
            vec = testCase.runFit(zClicked_mm, clicks, zAll_mm);

            testCase.verifyEqual(size(vec, 1), 1, 'Output must be a row vector');
            testCase.verifyEqual(size(vec, 2), 125);
            testCase.verifyHardInvariants(vec, zAll_mm);

            % All depths above the tissue share the z = 0 focus (hinge)
            testCase.verifyEqual(numel(unique(vec(zAll_mm <= 0))), 1);
        end
    end
end
