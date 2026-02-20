classdef test_yOCTScannerState < matlab.unittest.TestCase
    % Verify that StateGet and StateSet share a single source of truth.
    %
    % Before the fix, each function had its own persistent variable,
    % so writing via StateSet was invisible to StateGet.

    methods(TestMethodSetup)
        function resetState(~)
            % Start every test from a clean slate
            % yOCTScannerState('reset');
        end
    end

    methods(Test)
        function testSetTrueGetTrue(testCase)
            % Write true via StateSet, read via StateGet — must agree.
            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet(), ...
                'StateGet should return true after StateSet(true)');
        end

        function testSetFalseGetFalse(testCase)
            % Write false via StateSet after a true, read via StateGet.
            yOCTScannerStateSet(true);
            yOCTScannerStateSet(false);
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'StateGet should return false after StateSet(false)');
        end

        function testDefaultIsFalse(testCase)
            % After reset, state should default to false.
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'Default scanner state should be false');
        end
    end
end
