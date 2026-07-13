function tests = testNpyRecordingLoaders
% Camera-free integration tests for single/chunked NPY loader APIs.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testsDir = fileparts(mfilename('fullpath'));
analysisDir = fileparts(testsDir);
baseFuncDir = fullfile(analysisDir,'baseFunc');
addpath(baseFuncDir);
testCase.TestData.baseFuncDir = baseFuncDir;
py.importlib.import_module('numpy');
end

function teardownOnce(testCase)
rmpath(testCase.TestData.baseFuncDir);
end

function setup(testCase)
testCase.TestData.recordingDir = tempname;
mkdir(testCase.TestData.recordingDir);
end

function teardown(testCase)
if exist(testCase.TestData.recordingDir,'dir') == 7
    try
        py.gc.collect();
    catch
    end
    rmdir(testCase.TestData.recordingDir,'s');
end
end

function testLegacySingleFileWithoutPerFrameMetadata(testCase)
folder = testCase.TestData.recordingDir;
localWriteFrames(fullfile(folder,'frames.npy'),0,4);
localWriteJson(folder,struct('config',struct( ...
    'exposure_time',1000,'acquisition_frame_rate',100)));

[timeVec,info,sources] = LoadNpyRecordingMeta(folder);
verifySize(testCase,timeVec,[4 1]);
verifyTrue(testCase,all(isnan(timeVec)));
verifyEmpty(testCase,info.exposureTimesUs);
verifyEmpty(testCase,info.sequencerSetIds);
verifyEqual(testCase,info.exposureMode,'fixed');
verifyEqual(testCase,info.exposureSequenceUs,1000);
verifyEqual(testCase,sources.storageMode,'single');

[range,rangeTime,rangeInfo] = LoadNpyRecordingRange(folder,2,2);
verifySize(testCase,range,[2 3 2]);
verifyEqual(testCase,squeeze(range(1,1,:)),uint16([6;12]));
verifyTrue(testCase,all(isnan(rangeTime)));
verifyEmpty(testCase,rangeInfo.exposureTimesUs);

[frame,t,~,frameInfo] = LoadNpyRecordingFrame(folder,3,sources);
verifySize(testCase,frame,[2 3]);
verifyEqual(testCase,frame(1,1),uint16(12));
verifyTrue(testCase,isnan(t));
verifyEmpty(testCase,frameInfo.exposureTimesUs);
verifyEqual(testCase,frameInfo.exposureMode,'fixed');
verifyEqual(testCase,frameInfo.exposureSequenceUs,1000);
end

function testSingleFilePerFrameMetadataAndFullLoader(testCase)
folder = testCase.TestData.recordingDir;
localWriteFrames(fullfile(folder,'frames.npy'),0,4);
localWriteVector(fullfile(folder,'timestamps_camera_us.npy'),[0 1000 2500 4000],'float64');
localWriteVector(fullfile(folder,'exposure_times_us.npy'),[1000 10000 1000 10000],'float64');
localWriteVector(fullfile(folder,'sequencer_set_ids.npy'),[0 1 0 1],'int64');
metadata = struct('exposure_mode','sequencer', ...
    'exposure_sequence_us',[1000 10000], ...
    'config',struct('acquisition_frame_rate',100));
localWriteJson(folder,metadata);

[timeVec,info,sources] = LoadNpyRecordingMeta(folder);
verifyEqual(testCase,timeVec,[0;0.001;0.0025;0.004],'AbsTol',1e-12);
verifyEqual(testCase,info.exposureTimesUs,[1000;10000;1000;10000]);
verifyEqual(testCase,info.sequencerSetIds,[0;1;0;1]);
verifyEqual(testCase,info.exposureMode,'sequencer');
verifyEqual(testCase,info.exposureSequenceUs,[1000 10000]);

[recording,fullTime,fullInfo] = LoadNpyRecording(folder);
verifySize(testCase,recording,[2 3 4]);
verifyEqual(testCase,fullTime,timeVec);
verifyEqual(testCase,fullInfo.exposureTimesUs,info.exposureTimesUs);

[frame,t,~,frameInfo] = LoadNpyRecordingFrame(folder,4,sources);
verifyEqual(testCase,frame(1,1),uint16(18));
verifyEqual(testCase,t,0.004,'AbsTol',1e-12);
verifyEqual(testCase,frameInfo.timestampsCameraUs,4000);
verifyEqual(testCase,frameInfo.exposureTimesUs,10000);
verifyEqual(testCase,frameInfo.sequencerSetIds,1);
verifyEqual(testCase,frameInfo.exposureMode,'sequencer');
end

function testChunkBoundaryRangeAndStaleManifest(testCase)
folder = testCase.TestData.recordingDir;
localWriteFrames(fullfile(folder,'frames_00000000_00000001.npy'),0,2);
localWriteFrames(fullfile(folder,'frames_00000002_00000004.npy'),12,3);
localWriteChunkMetadata(folder,0,1,[0 1000],[1000 10000],[0 1]);
localWriteChunkMetadata(folder,2,4,[2500 4000 6000],[1000 10000 1000],[0 1 0]);

% Simulate a crash after the second frame chunk became durable but before
% metadata.json was updated. Strict directory enumeration must retain it.
metadata = struct('frame_files',{{'frames_00000000_00000001.npy'}}, ...
    'exposure_mode','sequencer','exposure_sequence_us',[1000 10000]);
localWriteJson(folder,metadata);
tmpPath = fullfile(folder,'frames_00000005_00000005.npy.tmp');
fid = fopen(tmpPath,'w'); fwrite(fid,uint8(1)); fclose(fid);

[~,info,sources] = LoadNpyRecordingMeta(folder);
verifyEqual(testCase,sources.totalFrames,5);
verifyEqual(testCase,numel(sources.framePaths),2);
verifyEqual(testCase,info.exposureTimesUs,[1000;10000;1000;10000;1000]);

[recording,timeVec,rangeInfo,rangeSources] = LoadNpyRecordingRange(folder,2,3);
verifySize(testCase,recording,[2 3 3]);
verifyEqual(testCase,squeeze(recording(1,1,:)),uint16([6;12;18]));
verifyEqual(testCase,timeVec,[0.001;0.0025;0.004],'AbsTol',1e-12);
verifyEqual(testCase,rangeInfo.exposureTimesUs,[10000;1000;10000]);
verifyEqual(testCase,rangeInfo.sequencerSetIds,[1;0;1]);
verifyEqual(testCase,rangeSources.selectionStartFrame,2);
verifyEqual(testCase,rangeSources.selectionFrameCount,3);
end

function testMissingMetadataChunkIsRejected(testCase)
folder = testCase.TestData.recordingDir;
localWriteFrames(fullfile(folder,'frames_00000000_00000001.npy'),0,2);
localWriteFrames(fullfile(folder,'frames_00000002_00000003.npy'),12,2);
localWriteVector(fullfile(folder,'exposure_times_us_00000000_00000001.npy'),[1000 10000],'float64');

verifyError(testCase,@() LoadNpyRecordingMeta(folder), ...
    'LoadNpyRecordingMeta:MetadataRangeMismatch');
end

function testFrameAndRangeBoundsAreOneBased(testCase)
folder = testCase.TestData.recordingDir;
localWriteFrames(fullfile(folder,'frames.npy'),0,3);
[~,~,sources] = LoadNpyRecordingMeta(folder);
verifyError(testCase,@() LoadNpyRecordingRange(folder,0,1), ...
    'LoadNpyRecordingMeta:Range');
verifyError(testCase,@() LoadNpyRecordingFrame(folder,0,sources), ...
    'LoadNpyRecordingFrame:Range');
verifyError(testCase,@() LoadNpyRecordingFrame(folder,4,sources), ...
    'LoadNpyRecordingFrame:Range');
end

function localWriteChunkMetadata(folder,startIndex,endIndex,timestamps,exposures,setIds)
suffix = sprintf('_%08d_%08d.npy',startIndex,endIndex);
localWriteVector(fullfile(folder,['timestamps_camera_us' suffix]),timestamps,'float64');
localWriteVector(fullfile(folder,['exposure_times_us' suffix]),exposures,'float64');
localWriteVector(fullfile(folder,['sequencer_set_ids' suffix]),setIds,'int64');
end

function localWriteFrames(path,startValue,count)
np = py.importlib.import_module('numpy');
first = int64(startValue);
last = int64(startValue + count*6);
array = np.arange(first,last,pyargs('dtype','uint16'));
array = array.reshape(int64(count),int64(2),int64(3));
np.save(path,array,pyargs('allow_pickle',false));
end

function localWriteVector(path,values,dtypeName)
np = py.importlib.import_module('numpy');
pythonValues = py.list(num2cell(values(:)'));
array = np.array(pythonValues,pyargs('dtype',dtypeName));
np.save(path,array,pyargs('allow_pickle',false));
end

function localWriteJson(folder,value)
path = fullfile(folder,'metadata.json');
fid = fopen(path,'w');
if fid < 0
    error('testNpyRecordingLoaders:Fixture','Could not create %s',path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value),'char');
end
