classdef test_yOCTScannerState < matlab.unittest.TestCase
    % Verify that StateGet and StateSet share a single source of truth.

    methods(Test)
        function testScannerStateSetterAndGetter(testCase)
            % set true: get must be true
            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet(), ...
                'StateGet should return true after StateSet(true)');

            % set false: get must be false (state actually changed)
            yOCTScannerStateSet(false);
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'StateGet should return false after StateSet(false)');

            % set true again: get must be true (not frozen at false)
            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet(), ...
                'StateGet should return true after second StateSet(true)');
        end
    end
end
