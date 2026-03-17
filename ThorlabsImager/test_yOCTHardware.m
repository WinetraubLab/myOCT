classdef test_yOCTHardware < matlab.unittest.TestCase
    % All tests use skipHardware=true so no real DLL or Python module is
    % needed. What we verify is pure cache and state logic.

    methods(TestMethodSetup)
        function resetCache(~)
            yOCTHardware('reset');
        end
    end

    methods(TestMethodTeardown)
        function cleanupCache(~)
            yOCTHardware('reset');
        end
    end

    methods(Test)

        %% Init: first call caches all outputs
        function testFirstCallCachesAllOutputs(testCase)
            [module, name, skip, scanInit] = yOCTHardware('init', 'Gan632', true, '');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized when skipHardware=true');
        end

        %% Init: early return with same args
        function testEarlyReturnWithSameArgs(testCase)
            yOCTHardware('init', 'Gan632', true, '');
            [module, name, skip, scanInit] = yOCTHardware('init', 'Gan632', true, '');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit);
        end

        %% Status: returns cache with all outputs
        function testStatusReturnsCache(testCase)
            yOCTHardware('init', 'Gan632', true, '');
            [module, name, skip, scanInit] = yOCTHardware('status');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized with skipHardware=true');
        end

        %% Status: errors when not initialized
        function testStatusErrorsWhenNotInitialized(testCase)
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% Teardown: safe when never initialized
        function testTeardownWithoutInitIsSafe(testCase)
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit);
        end

        %% Teardown: clears cache and scanner state
        function testTeardownClearsCache(testCase)
            yOCTHardware('init', 'Gan632', true, '');
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after teardown');

            % Cache must be empty: status errors
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');

            % Re-init with a different system must work
            [~, name, skip] = yOCTHardware('init', 'Ganymede', true, '');
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% System name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            yOCTHardware('init', 'Gan632', true, '');
            [~, name, ~] = yOCTHardware('init', 'Ganymede', true, '');
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            yOCTHardware('init', 'Ganymede', true, '');
            [~, name, ~] = yOCTHardware('init', 'Gan632', true, '');
            testCase.verifyEqual(name, 'gan632');
        end

        %% Reset: clears cache and scanner state
        function testResetClearsCache(testCase)
            yOCTHardware('init', 'Gan632', true, '');
            [~, ~, ~, scanInit] = yOCTHardware('reset');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after reset');
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% Invalid command errors
        function testInvalidCommandErrors(testCase)
            testCase.verifyError(@() yOCTHardware('bogus'), ...
                'myOCT:yOCTHardware:unknownCommand');
        end

        %% No command errors
        function testNoCommandErrors(testCase)
            testCase.verifyError(@() yOCTHardware(''), ...
                'myOCT:yOCTHardware:noCommand');
        end

    end
end
