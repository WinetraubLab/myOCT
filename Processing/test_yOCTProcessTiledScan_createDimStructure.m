classdef test_yOCTProcessTiledScan_createDimStructure < matlab.unittest.TestCase
    % Tests for the galvo phase delay X-correction in yOCTProcessTiledScan_createDimStructure.
    %
    %   At low pixel resolutions the galvo mirror lags behind the commanded
    %   position, so the X coordinates written in the OCT file are wrong.
    %   yOCTProcessTiledScan_createDimStructure fixes this by shifting
    %   dimOneTile.x.values by N*(pixelSize_um - 1)*1e-3 mm, where N is
    %   the GalvoPhaseDelay_Asamples value stored in the probe .ini file.
    %   After this shift every downstream function (optical path correction,
    %   tile stitching, surface detection) automatically receives the
    %   correct physical beam positions.
    %
    %   Each test creates a simulated scan on disk, sets the desired
    %   parameters in ScanInfo.json, calls createDimStructure, and checks
    %   that x.values came out with the expected values.

    methods(TestClassSetup)
        function setupHardwareLib(~)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
        end
    end

    properties (Access = private)
        TestFolder = 'tmp_galvo_phase_delay_test/'
    end

    methods (Access = private)
        function simulateScan(testCase, nXPixels, pixelSize_um, galvoPhaseDelay_Asamples)
            % Creates a simulated tile scan folder on disk with the given pixel
            % size and number of X columns. If galvoPhaseDelay_Asamples is
            % non-zero it is written into ScanInfo.json so that
            % createDimStructure can read and apply it.
            % Pass galvoPhaseDelay_Asamples = 0 to leave the field absent.

            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's');
            end
            dummyData = zeros(512, nXPixels, 2) + 1;
            octProbePath = yOCTGetProbeIniPath('20x', 'OCTG', '');
            yOCTSimulateTileScan(dummyData, testCase.TestFolder, ...
                'pixelSize_um', pixelSize_um, ...
                'zDepths', 0, ...
                'focusPositionInImageZpix', 250, ...
                'focusSigma', 1, ...
                'octProbePath', octProbePath);

            if galvoPhaseDelay_Asamples ~= 0
                json = awsReadJSON([testCase.TestFolder 'ScanInfo.json']);
                json.octProbe.GalvoPhaseDelay_Asamples = galvoPhaseDelay_Asamples;
                awsWriteJSON(json, [testCase.TestFolder 'ScanInfo.json']);
            end
        end

        function x_mm = uncorrectedXFromJson(~, json)
            % Returns what x.values would be if NO galvo correction were
            % applied, like the raw commanded positions from the JSON.
            % Used as the reference baseline in each test.
            x_mm = json.xOffset + ...
                json.tileRangeX_mm * linspace(-0.5, 0.5, json.nXPixelsInEachTile + 1);
            x_mm(end) = [];
        end

        function cleanup(testCase)
            if exist(testCase.TestFolder, 'dir')
                rmdir(testCase.TestFolder, 's');
            end
        end
    end

    methods(Test)
        function testNoOpAtCalibrationPixelSize(testCase)
            % The correction formula is N*(pixelSize - 1um). At 1 um/pixel
            % (the resolution where the probe polynomial was calibrated)
            % this evaluates to N*(1-1) = 0 regardless of N. So x.values
            % must be identical to the raw commanded positions. The fix
            % must be a complete no operation at high resolution.

            testCase.simulateScan(500, 1, 15.5);
            testCase.addTeardown(@() testCase.cleanup());

            [dimOneTile, ~] = yOCTProcessTiledScan_createDimStructure(testCase.TestFolder);
            json = awsReadJSON([testCase.TestFolder 'ScanInfo.json']);

            testCase.verifyEqual(dimOneTile.x.values, testCase.uncorrectedXFromJson(json), ...
                'AbsTol', 1e-9, ...
                'At calibration pixel size the correction must be a no operation done');
        end

        function testCorrectShiftAtLowResolution(testCase)
            % At low resolution the galvo lag in microns is large. This
            % test uses the real calibrated value for the 20x OCTG probe:
            % N = 15.5 samples at 20 um/pixel => shift = 15.5*(20-1)*1e-3
            % = 0.2945 mm. It checks three things:
            %   1. dimOneTile.x.values shifted by exactly 0.2945 mm.
            %   2. dimOutput.x.values (the full-volume grid) inherited the
            %      same shift so tile stitching is also correct.
            %   3. The spacing between adjacent x values did NOT change:
            %      a constant shift must never affect pixel size.

            pixelSize_um = 20;
            N = 15.5;
            testCase.simulateScan(24, pixelSize_um, N);
            testCase.addTeardown(@() testCase.cleanup());

            [dimOneTile, dimOutput] = yOCTProcessTiledScan_createDimStructure(testCase.TestFolder);
            json = awsReadJSON([testCase.TestFolder 'ScanInfo.json']);

            calibrationPixelSize_um = 1;
            expectedShift_mm = N * (pixelSize_um - calibrationPixelSize_um) * 1e-3;
            uncorrected = testCase.uncorrectedXFromJson(json);
            expected = uncorrected - expectedShift_mm;

            testCase.verifyEqual(dimOneTile.x.values, expected, ...
                'AbsTol', 1e-9, ...
                'Per-tile X must shift by N*(dx-1)*1e-3 mm');

            % Global output X inherits the same shift (single-tile test).
            testCase.verifyEqual(dimOutput.x.values(1) - uncorrected(1), -expectedShift_mm, ...
                'AbsTol', 1e-9, ...
                'Global output X must inherit the correction');

            % Constant subtraction must not change pixel spacing.
            testCase.verifyEqual(diff(dimOneTile.x.values), diff(uncorrected), ...
                'AbsTol', 1e-12, 'Pixel spacing must be unchanged');
        end

        function testBackwardsCompatibleNoField(testCase)
            % Probes that have never been galvo-delay calibrated do not have 
            % GalvoPhaseDelay_Asamples in their .ini file, so the field will
            % be absent from ScanInfo.json. In that case the correction must
            % default to zero: existing scans from these probes must be completely 
            % unaffected by this change.

            % The 20x OCTG .ini already has the field, so after simulating
            % we manually remove it from ScanInfo.json to replicate what
            % an uncalibrated probe scan looks like on disk:
            testCase.simulateScan(24, 20, 0);
            testCase.addTeardown(@() testCase.cleanup());

            % Remove the field to simulate an uncalibrated probe
            json = awsReadJSON([testCase.TestFolder 'ScanInfo.json']);
            json.octProbe = rmfield(json.octProbe, 'GalvoPhaseDelay_Asamples');
            awsWriteJSON(json, [testCase.TestFolder 'ScanInfo.json']);

            [dimOneTile, ~] = yOCTProcessTiledScan_createDimStructure(testCase.TestFolder);
            json = awsReadJSON([testCase.TestFolder 'ScanInfo.json']);

            % Confirm the field is really gone before checking x.values
            testCase.verifyFalse( ...
                isfield(json.octProbe, 'GalvoPhaseDelay_Asamples'), ...
                'Precondition: field must have been removed from ScanInfo.json');

            testCase.verifyEqual(dimOneTile.x.values, testCase.uncorrectedXFromJson(json), ...
                'AbsTol', 1e-9, ...
                'Without GalvoPhaseDelay_Asamples there must be no shift');
        end
    end
end
