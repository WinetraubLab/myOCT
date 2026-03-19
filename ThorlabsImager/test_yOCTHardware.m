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

    methods(Static, Access = private)
        function initAndThrow()
            % Helper: init + onCleanup + throw, mirroring the script pattern.
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            cleanupObj = onCleanup(@() yOCTHardware('teardown')); %#ok<NASGU>
            error('test:deliberate', 'Simulated script error');
        end
    end

    methods(Test)

        %% Init: first call caches all outputs
        function testFirstCallCachesAllOutputs(testCase)
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit, ...
                'Scanner should not be initialized when skipHardware=true');
        end

        %% Init: early return with same args
        function testEarlyReturnWithSameArgs(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [module, name, skip, scanInit] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
            testCase.verifyFalse(scanInit);
        end

        %% Status: returns cache with all outputs
        function testStatusReturnsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
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

        %% verifyInit: errors when not initialized
        function testVerifyInitErrorsWhenNotInitialized(testCase)
            testCase.verifyError(@() yOCTHardware('verifyInit'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% verifyInit: passes when skipHardware=true (scanner not needed)
        function testVerifyInitPassesWithSkipHardware(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, name, skip] = yOCTHardware('verifyInit');
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyTrue(skip);
        end

        %% Teardown: safe when never initialized
        function testTeardownWithoutInitIsSafe(testCase)
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit);
        end

        %% Teardown: clears cache and scanner state
        function testTeardownClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, ~, ~, scanInit] = yOCTHardware('teardown');
            testCase.verifyFalse(scanInit, ...
                'Scanner state should be false after teardown');

            % Cache must be empty: status errors
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');

            % Re-init with a different system must work
            [~, name, skip] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% System name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Ganymede', 'skipHardware', true);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            yOCTHardware('init', 'OCTSystem', 'Ganymede', 'skipHardware', true);
            [~, name, ~] = yOCTHardware('init', ...
                'OCTSystem', 'Gan632', 'skipHardware', true);
            testCase.verifyEqual(name, 'gan632');
        end

        %% onCleanup: teardown runs even when function throws
        function testOnCleanupRunsTeardownOnError(testCase)
            % Simulate the script pattern: init + onCleanup + error.
            % When the helper function exits (via error), onCleanup fires
            % teardown, clearing the cache.
            try
                test_yOCTHardware.initAndThrow();
            catch
                % Expected — the helper threw on purpose.
            end
            % If onCleanup fired teardown, cache is empty now.
            testCase.verifyError(@() yOCTHardware('status'), ...
                'myOCT:yOCTHardware:notInitialized');
        end

        %% Reset: clears cache and scanner state
        function testResetClearsCache(testCase)
            yOCTHardware('init', 'OCTSystem', 'Gan632', 'skipHardware', true);
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
