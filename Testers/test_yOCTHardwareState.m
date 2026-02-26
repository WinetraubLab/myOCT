classdef test_yOCTHardwareState < matlab.unittest.TestCase
    % Central hardware state store and the functions that depend on it:
    %   yOCTHardwareState         - central persistent store
    %   yOCTScannerStateGet/Set   - scanner initialized flag
    %   yOCTHardwareLibSetUp      - library cache + early-return 
    %   yOCTHardwareLibTearDown   - cleanup + cache clearing
    %
    % All tests use skipHardware=true so no real DLL or Python module is
    % needed.  What we verify is pure state / cache logic.

    methods(TestMethodSetup)
        function resetBefore(~)
            yOCTHardwareState('reset');
        end
    end

    methods(TestMethodTeardown)
        function resetAfter(~)
            yOCTHardwareState('reset');
        end
    end

    methods(Test)
        %%  Scanner state
        function testScannerStateSetGetShareState(testCase)
            % Set(true) must be visible to Get().
            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet(), ...
                'StateGet should return true after StateSet(true)');
        end

        function testScannerStateRoundTrip(testCase)
            % Full round-trip: true -> false -> true
            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet());

            yOCTScannerStateSet(false);
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'StateGet should return false after StateSet(false)');

            yOCTScannerStateSet(true);
            testCase.verifyTrue(yOCTScannerStateGet(), ...
                'StateGet should return true after second StateSet(true)');
        end

        function testScannerStateDefaultIsFalse(testCase)
            % On a fresh store, scanner must report "not initialized".
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'Default scanner state should be false');
        end

        function testScannerStateResetClearsFlag(testCase)
            % After a store reset, scanner flag goes back to false.
            yOCTScannerStateSet(true);
            yOCTHardwareState('reset');
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'Scanner state should be false after store reset');
        end

        %%  Hardware library cache
        function testFirstCallCachesAllOutputs(testCase)
            % First call must return the lowercased name, empty module.
            [module, name, skip] = yOCTHardwareLibSetUp('Gan632', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
        end

        function testEarlyReturnWithSameArgs(testCase)
            % Calling SetUp again with the SAME args must early-return.
            yOCTHardwareLibSetUp('Gan632', true);
            [module, name, skip] = yOCTHardwareLibSetUp('Gan632', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
        end

        function testEarlyReturnWithNoArgs(testCase)
            % SetUp() with no arguments must return the full cache.
            yOCTHardwareLibSetUp('Gan632', true);
            [module, name, skip] = yOCTHardwareLibSetUp();
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
        end

        function testSetUpWithoutArgsBeforeInitErrors(testCase)
            % SetUp() with no args and no cache must throw.
            testCase.verifyError(@() yOCTHardwareLibSetUp(), ...
                'myOCT:yOCTHardwareLibSetUp:noSystemName');
        end

        %%  TearDown clears cache
        function testTearDownWithoutSetUpIsSafe(testCase)
            % TearDown called before any SetUp must return silently
            testCase.verifyWarningFree(@() yOCTHardwareLibTearDown());
        end

        function testTearDownClearsCache(testCase)
            % After TearDown the cache is empty: SetUp() with no args
            % errors, and re-init with a different system succeeds.
            yOCTHardwareLibSetUp('Gan632', true);
            yOCTHardwareLibTearDown();

            % Cache must be empty now
            testCase.verifyError(@() yOCTHardwareLibSetUp(), ...
                'myOCT:yOCTHardwareLibSetUp:noSystemName');

            % Re-init with a different system must work cleanly
            [~, name, skip] = yOCTHardwareLibSetUp('Ganymede', true);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        function testTearDownClearsScannerState(testCase)
            % Scanner flag must be false after TearDown.
            yOCTHardwareLibSetUp('Ganymede', true);
            yOCTScannerStateSet(true);
            yOCTHardwareLibTearDown();
            testCase.verifyFalse(yOCTScannerStateGet(), ...
                'Scanner state should be false after TearDown');
        end

        %%  System name / skipHardware change detection
        function testSystemNameChangeGan632ToGanymede(testCase)
            % Gan632 -> Ganymede without TearDown must re init.
            yOCTHardwareLibSetUp('Gan632', true);
            [~, name, ~] = yOCTHardwareLibSetUp('Ganymede', true);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            % Ganymede -> Gan632 without TearDown must re init.
            yOCTHardwareLibSetUp('Ganymede', true);
            [~, name, ~] = yOCTHardwareLibSetUp('Gan632', true);
            testCase.verifyEqual(name, 'gan632');
        end

        %%  Central store direct access
        function testStoreIsLoadedReflectsSetUp(testCase)
            testCase.verifyFalse(yOCTHardwareState('isLoaded'), ...
                'Store should not be loaded before SetUp');
            yOCTHardwareLibSetUp('Ganymede', true);
            testCase.verifyTrue(yOCTHardwareState('isLoaded'), ...
                'Store should be loaded after SetUp');
        end

        function testStoreResetClearsEverything(testCase)
            yOCTHardwareLibSetUp('Gan632', true);
            yOCTScannerStateSet(true);
            yOCTHardwareState('reset');

            testCase.verifyFalse(yOCTHardwareState('isLoaded'));
            testCase.verifyFalse(yOCTScannerStateGet());
        end

        function testStoreBadActionErrors(testCase)
            testCase.verifyError( ...
                @() yOCTHardwareState('mustfail'), ...
                'myOCT:yOCTHardwareState:badAction');
        end

    end
end
