function tests = testExposureGroupingAndTimeAxis
% Unit tests for exposure grouping and timestamp-based series extraction.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testsDir = fileparts(mfilename('fullpath'));
analysisDir = fileparts(testsDir);
baseFuncDir = fullfile(analysisDir,'baseFunc');
addpath(baseFuncDir);
testCase.TestData.baseFuncDir = baseFuncDir;
end

function teardownOnce(testCase)
rmpath(testCase.TestData.baseFuncDir);
end

function testLegacyFixedExposureWithoutPerFrameFile(testCase)
[groups, values, details] = GroupExposureFrames([], 1000, 4);
verifyEqual(testCase, groups, ones(4,1));
verifyEqual(testCase, values, 1000);
verifyFalse(testCase, details.isMultipleExposure);
end

function testSingleElementSequencer(testCase)
[groups, values, details] = GroupExposureFrames([1000.1 999.9 1000], 1000, 3);
verifyEqual(testCase, groups, ones(3,1));
verifyEqual(testCase, values, 1000);
verifyFalse(testCase, details.isMultipleExposure);
verifyEqual(testCase, details.actualMedianUs, 1000, 'AbsTol', 1e-12);
end

function testMultipleExposureUsesToleranceAndSequenceOrder(testCase)
applied = [999.9 9999.8 1000.1 10000.2]';
[groups, values, details] = GroupExposureFrames(applied, [1000 10000], 4);
verifyEqual(testCase, groups, [1 2 1 2]');
verifyEqual(testCase, values, [1000 10000]);
verifyTrue(testCase, details.isMultipleExposure);
end

function testDuplicateRequestedExposureIsOneCondition(testCase)
[groups, values] = GroupExposureFrames(1000 * ones(4,1), [1000 1000], 4);
verifyEqual(testCase, groups, ones(4,1));
verifyEqual(testCase, values, 1000);
end

function testConfiguredButUnobservedExposureIsReportedNotFatal(testCase)
[groups, values, details] = GroupExposureFrames([1000 1000]', [1000 10000], 2);
verifyEqual(testCase, groups, ones(2,1));
verifyEqual(testCase, values, 1000);
verifyEqual(testCase, details.unusedSequenceUs, 10000);
verifyEqual(testCase, details.sequenceToGroup, [1 0]);
end

function testFirstConfiguredExposureMayBeUnobserved(testCase)
[groups, values, details] = GroupExposureFrames([10000 10000]', [1000 10000], 2);
verifyEqual(testCase, groups, ones(2,1));
verifyEqual(testCase, values, 10000);
verifyEqual(testCase, details.unusedSequenceUs, 1000);
verifyEqual(testCase, details.sequenceToGroup, [0 1]);
end

function testMissingPerFrameMetadataForMultipleSequenceFails(testCase)
verifyError(testCase, @() GroupExposureFrames([], [1000 10000], 4), ...
    'GroupExposureFrames:MissingPerFrameExposure');
end

function testInvalidPartialExposureMetadataFails(testCase)
verifyError(testCase, @() GroupExposureFrames([1000 NaN], 1000, 2), ...
    'GroupExposureFrames:InvalidPerFrameExposure');
end

function testCameraTimestampSubsetsSurviveDroppedFrame(testCase)
exposure = [1000 10000 10000 1000]';
[groups, ~] = GroupExposureFrames(exposure, [1000 10000], 4);
[allTime, usedCamera] = BuildExposureTimeAxis([20.00 20.01 20.03 20.04]', 4, 100);

verifyTrue(testCase, usedCamera);
verifyEqual(testCase, allTime(groups == 1), [0 0.04]', 'AbsTol', 1e-12);
verifyEqual(testCase, allTime(groups == 2), [0.01 0.03]', 'AbsTol', 1e-12);
end

function testDatenumTimestampConversion(testCase)
t0 = datenum(2026,7,11,12,0,0);
[allTime, usedCamera] = BuildExposureTimeAxis(t0 + [0 0.1 0.25]' ./ 86400, 3, 10);
verifyTrue(testCase, usedCamera);
verifyEqual(testCase, allTime, [0 0.1 0.25]', 'AbsTol', 1e-5);
end

function testLegacyTimestampFallback(testCase)
[allTime, usedCamera] = BuildExposureTimeAxis(nan(4,1), 4, 20);
verifyFalse(testCase, usedCamera);
verifyEqual(testCase, allTime, [0 0.05 0.10 0.15]', 'AbsTol', 1e-12);
end

function testPartialTimestampVectorFails(testCase)
verifyError(testCase, @() BuildExposureTimeAxis([0 NaN 0.02]', 3, 100), ...
    'BuildExposureTimeAxis:PartialTimestamps');
end
