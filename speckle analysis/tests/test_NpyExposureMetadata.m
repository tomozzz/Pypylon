function tests = test_NpyExposureMetadata
% Function-based tests for legacy and exposure-aware NPY loading.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testDir = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(testDir),'baseFunc'));
testCase.TestData.np = py.importlib.import_module('numpy');
end

function testLegacyFolderWithoutExposureFiles(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
np = testCase.TestData.np;
frames = np.zeros(py.tuple({int32(3),int32(2),int32(2)}),pyargs('dtype','uint16'));
np.save(fullfile(folder,'frames.npy'),frames);

[timeVec,info,sourceFiles] = LoadNpyRecordingMeta(folder);
verifyEqual(testCase,sourceFiles.totalFrames,3);
verifyEmpty(testCase,sourceFiles.exposureTimesUs);
verifyEmpty(testCase,sourceFiles.sequencerSetIds);
verifyTrue(testCase,all(isnan(timeVec)));
verifyEqual(testCase,info.exposureMode,'fixed');
end

function testChunkedRangeKeepsExposureAlignment(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
np = testCase.TestData.np;

np.save(fullfile(folder,'frames_00000000_00000001.npy'), ...
    np.zeros(py.tuple({int32(2),int32(2),int32(2)}),pyargs('dtype','uint16')));
np.save(fullfile(folder,'frames_00000002_00000004.npy'), ...
    np.ones(py.tuple({int32(3),int32(2),int32(2)}),pyargs('dtype','uint16')));
localSaveVector(np,folder,'timestamps_camera_us_00000000_00000001.npy',[0 100]);
localSaveVector(np,folder,'timestamps_camera_us_00000002_00000004.npy',[200 300 400]);
localSaveVector(np,folder,'exposure_times_us_00000000_00000001.npy',[1000 10000]);
localSaveVector(np,folder,'exposure_times_us_00000002_00000004.npy',[1000 10000 1000]);
localSaveVector(np,folder,'sequencer_set_ids_00000000_00000001.npy',int64([0 1]));
localSaveVector(np,folder,'sequencer_set_ids_00000002_00000004.npy',int64([0 1 0]));
% Simulate metadata renamed before a hard stop; without a matching final
% frames file this orphan chunk must not affect reconstruction.
localSaveVector(np,folder,'exposure_times_us_00000005_00000006.npy',[10000 1000]);

[rec,timeVec,info,sourceFiles] = LoadNpyRecordingRange(folder,2,3);
verifyEqual(testCase,size(rec),[2 2 3]);
verifyEqual(testCase,info.exposureTimesUs,[10000;1000;10000]);
verifyEqual(testCase,double(info.sequencerSetIds),[1;0;1]);
verifyEqual(testCase,timeVec,[0.0001;0.0002;0.0003],'AbsTol',1e-12);
verifyEqual(testCase,sourceFiles.rangeStartFrame,2);
verifyEqual(testCase,sourceFiles.rangeEndFrame,4);
end

function testExposureGroupingUsesSavedTimestamps(testCase)
exposures = [1000;10000;1000;10000];
timeVec = [0;0.011;0.021;0.033];
groups = GroupFramesByExposure(exposures,timeVec);
verifyEqual(testCase,numel(groups),2);
verifyEqual(testCase,groups(1).frameIndices,[1;3]);
verifyEqual(testCase,groups(1).timeVec,[0;0.021]);
verifyEqual(testCase,groups(2).frameIndices,[2;4]);
verifyEqual(testCase,groups(2).timeVec,[0.011;0.033]);

singleGroup = GroupFramesByExposure(1000*ones(4,1),timeVec);
verifyEqual(testCase,numel(singleGroup),1);
verifyEqual(testCase,singleGroup.frameIndices,(1:4)');
end

function localSaveVector(np,folder,name,values)
np.save(fullfile(folder,name),np.asarray(values));
end
