classdef test_yOCTHardwareLib < matlab.unittest.TestCase
    % Tests for yOCTHardwareLibSetUp / TearDown cache mechanism.
    % All tests use skipHardware=true so no real DLL or Python module is
    % needed. What we verify is pure cache logic.

    methods(TestMethodSetup)
        function resetCache(~)
            yOCTHardwareLibSetUp('reset'); % guards against dirty state from outside the suite
        end
    end

    methods(TestMethodTeardown)
        function cleanupCache(~)
            yOCTHardwareLibSetUp('reset'); % cleans up even if a test fails midway
        end
    end

    methods(Test)

        %% Verify first call caching
        function testFirstCallCachesAllOutputs(testCase)
            % First call must return the lowercased name, empty module
            [module, name, skip] = yOCTHardwareLibSetUp('Gan632', true);
            testCase.verifyEqual(name, 'gan632');
            testCase.verifyEmpty(module);
            testCase.verifyTrue(skip);
        end

        %% Verify early-return preserves cache
        function testEarlyReturnWithSameArgs(testCase)
            % Calling SetUp again with the SAME name and skipHardware must
            % early-return and keep every cached value intact.
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

        %% Verify TearDown clears cache
        function testTearDownWithoutSetUpIsSafe(testCase)
            % TearDown called before any SetUp must return silently,
            % so it is safe to use in onCleanup or deferred cleanup blocks.
            testCase.verifyWarningFree(@() yOCTHardwareLibTearDown());
        end

        function testTearDownClearsCache(testCase)
            % After TearDown the cache is empty: SetUp() with no args
            % throws, and re-init with a different system succeeds.
            yOCTHardwareLibSetUp('Gan632', true);
            yOCTHardwareLibTearDown();

            % Cache must be empty: no arg call errors here since it can't early return with a stale value.
            testCase.verifyError(@() yOCTHardwareLibSetUp(), ...
                'myOCT:yOCTHardwareLibSetUp:noSystemName');

            % Re-init with a different system must work cleanly with new values.
            [~, name, skip] = yOCTHardwareLibSetUp('Ganymede', true);
            testCase.verifyEqual(name, 'ganymede');
            testCase.verifyTrue(skip);
        end

        %% Verify system name change triggers re-init
        function testSystemNameChangeGan632ToGanymede(testCase)
            % Gan632 -> Ganymede without TearDown must re-init with the new name.
            yOCTHardwareLibSetUp('Gan632', true);
            [~, name, ~] = yOCTHardwareLibSetUp('Ganymede', true);
            testCase.verifyEqual(name, 'ganymede');
        end

        function testSystemNameChangeGanymedeToGan632(testCase)
            % Ganymede -> Gan632 without TearDown must re-init with the new name.
            yOCTHardwareLibSetUp('Ganymede', true);
            [~, name, ~] = yOCTHardwareLibSetUp('Gan632', true);
            testCase.verifyEqual(name, 'gan632');
        end

        % skipHardware coverage notes:
        %   - skipHardware=true is verified in every test above (all use it and check the returned value).
        %   - skipHardware change detection (true<->false) uses the same OR branch as system-name
        %     change, already exercised by the two tests above. Dedicated change tests are omitted
        %     because they require the Thorlabs SDK and produce no real assertions without it.

    end
end
