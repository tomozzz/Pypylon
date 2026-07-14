function tests = testScosRoiNoiseCorrection
% Camera-free end-to-end tests for ROI-specific SCOS calibration.
tests = functiontests(localfunctions);
end


function setupOnce(testCase)
testsDirectory = fileparts(mfilename('fullpath'));
analysisDirectory = fileparts(testsDirectory);
baseFunctionDirectory = fullfile(analysisDirectory,'baseFunc');
addpath(analysisDirectory,baseFunctionDirectory);
py.importlib.import_module('numpy');
testCase.TestData.analysisDirectory = analysisDirectory;
testCase.TestData.baseFunctionDirectory = baseFunctionDirectory;
end


function teardownOnce(testCase)
rmpath(testCase.TestData.analysisDirectory,testCase.TestData.baseFunctionDirectory);
end


function setup(testCase)
testRoot = tempname;
mkdir(testRoot);
recordingDirectory = fullfile(testRoot,'recording');
darkDirectory = fullfile(testRoot,'dark');
mkdir(recordingDirectory);
mkdir(darkDirectory);
testCase.TestData.testRoot = testRoot;
testCase.TestData.recordingDirectory = recordingDirectory;
testCase.TestData.darkDirectory = darkDirectory;
testCase.TestData.windowSize = 3;
testCase.TestData.masks = localMasks([12 12]);
end


function teardown(testCase)
if exist(testCase.TestData.testRoot,'dir') == 7
    try
        py.gc.collect();
    catch
    end
    rmdir(testCase.TestData.testRoot,'s');
end
close all force;
end


function testFixedExposureUsesRoiFitsAndOmitsQuantizationTerm(testCase)
recordingDirectory = testCase.TestData.recordingDirectory;
darkDirectory = testCase.TestData.darkDirectory;
windowSize = testCase.TestData.windowSize;
masks = testCase.TestData.masks;
localCreateFixture(recordingDirectory,darkDirectory,false);

% This is the old ROI-common, pre-spatial-shot-noise cache format. It must
% not be accepted as a completed calibration after the algorithm change.
spVar = zeros(12); %#ok<NASGU>
fitI_A = ones(12); %#ok<NASGU>
fitI_B = zeros(12); %#ok<NASGU>
spIm = zeros(12); %#ok<NASGU>
save(fullfile(recordingDirectory,'smoothingCoefficients.mat'), ...
    'spVar','fitI_A','fitI_B','spIm');

[~,~,~,~,info,results] = SCOSvsTime_WithNoiseSubtraction_Ver2( ...
    recordingDirectory,darkDirectory,windowSize,false,masks);

cache = load(fullfile(recordingDirectory,'smoothingCoefficients.mat'));
verifyEqual(testCase,cache.savedCalibrationVersion,2);
verifyEqual(testCase,numel(cache.spatialCalibration),1);
calibration = cache.spatialCalibration(1);
verifyEqual(testCase,numel(calibration.fitI_A_byCh),2);
verifyEqual(testCase,numel(calibration.fitI_B_byCh),2);
verifyGreaterThan(testCase, ...
    max(abs(calibration.fitI_A_byCh{1}(:)-calibration.fitI_A_byCh{2}(:))),1e-8);

expectedSpatialVariance = max(calibration.spVarRaw-calibration.spShotVar,0);
verifyEqual(testCase,calibration.spVar,expectedSpatialVariance,'AbsTol',1e-12);
verifyGreaterThan(testCase,max(calibration.spShotVar(:)),0);
verifyGreaterThan(testCase,nnz(calibration.spVar == 0),0);

[expectedWithoutQuantization,expectedWithQuantization] = localExpectedFirstFrame( ...
    recordingDirectory,darkDirectory,info,calibration,masks,windowSize,1);
actual = results.byExposure(1).corrSpeckleContrast(1,1);
verifyEqual(testCase,actual,expectedWithoutQuantization,'AbsTol',1e-12);
verifyGreaterThan(testCase,abs(actual-expectedWithQuantization),eps(max(abs(actual),1)));
end


function testMultipleExposureStandaloneNirsMatchesIndependentScos(testCase)
recordingDirectory = testCase.TestData.recordingDirectory;
darkDirectory = testCase.TestData.darkDirectory;
windowSize = testCase.TestData.windowSize;
masks = testCase.TestData.masks;
localCreateFixture(recordingDirectory,darkDirectory,true);

[~,~,~,~,~,scosResults] = SCOSvsTime_WithNoiseSubtraction_Ver2( ...
    recordingDirectory,darkDirectory,windowSize,false,masks);
nirsOptions = struct('wavelengthsNm',[785 830], ...
    'wavelengthSetIds',[0 1], ...
    'sourceDetectorChannels',[1 2], ...
    'sourceDetectorDistancesCm',[2 3], ...
    'baselineDurationS',0.05, ...
    'saveOutput',false, ...
    'plotNirs',false);
[~,~,~,~,~,standaloneResults,nirs] = ...
    SCOSNIRSvsTime_WithNoiseSubtraction_Ver2( ...
        recordingDirectory,darkDirectory,windowSize,false,masks,nirsOptions);

verifyEqual(testCase,numel(standaloneResults.byExposure),2);
for exposureIdx = 1:2
    verifyEqual(testCase,standaloneResults.byExposure(exposureIdx).meanIntensity, ...
        scosResults.byExposure(exposureIdx).meanIntensity,'AbsTol',1e-12);
    verifyEqual(testCase,standaloneResults.byExposure(exposureIdx).corrSpeckleContrast, ...
        scosResults.byExposure(exposureIdx).corrSpeckleContrast,'AbsTol',1e-12);
end
verifyTrue(testCase,isfield(standaloneResults,'nirs'));
verifyEqual(testCase,standaloneResults.nirs,nirs);
verifyEqual(testCase,nirs.wavelengthSetIds,[0 1]);
verifyEqual(testCase,nirs.frameIndices,[1 2;3 4;5 6;7 8]);
verifySize(testCase,nirs.rMRO2,[4 1]);
end


function testStandaloneNirsSourceDoesNotCallScosEntrypoint(testCase)
sourcePath = fullfile(testCase.TestData.analysisDirectory, ...
    'SCOSNIRSvsTime_WithNoiseSubtraction_Ver2.m');
sourceText = fileread(sourcePath);
callExpression = ['(?m)^\s*\[.*\]\s*=\s*\.\.\.\s*\r?\n\s*' ...
    'SCOSvsTime_WithNoiseSubtraction_Ver2\s*\('];
verifyEmpty(testCase,regexp(sourceText,callExpression,'once'));
verifyNotEmpty(testCase,regexp(sourceText, ...
    'function\s+spatialCalibration\s*=\s*localBuildSpatialCorrections','once'));
verifyNotEmpty(testCase,regexp(sourceText, ...
    'function\s+nirs\s*=\s*localCalculateNirsFromScosResults','once'));
end


function [withoutQuantization,withQuantization] = localExpectedFirstFrame( ...
        recordingDirectory,darkDirectory,info,calibration,masks,windowSize,channelIdx)
[~,~,sources] = LoadNpyRecordingMeta(recordingDirectory);
[rawFrame,~] = LoadNpyRecordingFrame(recordingDirectory,1,sources);
[darkRecord,~,~] = LoadNpyRecording(darkDirectory);
background = mean(double(darkRecord),3);
darkVariancePerWindow = imboxfilt(std(double(darkRecord),0,3).^2,windowSize);
actualGain = GetActualGain(info);

ws2 = ceil(windowSize/2);
trimmedMasks = masks;
for idx = 1:numel(trimmedMasks)
    trimmedMasks{idx}([1:ws2 (end-ws2+1):end],:) = false;
    trimmedMasks{idx}(:,[1:ws2 (end-ws2+1):end]) = false;
end
totalMask = trimmedMasks{1};
for idx = 2:numel(trimmedMasks)
    totalMask = totalMask | trimmedMasks{idx};
end
[y,x] = find(totalMask);
limits = [min(y)-windowSize max(y)+windowSize; ...
          min(x)-windowSize max(x)+windowSize];
limits(limits < 1) = 1;
limits(1,2) = min(limits(1,2),sources.imageSize(1));
limits(2,2) = min(limits(2,2),sources.imageSize(2));
roiY = limits(1,1):limits(1,2);
roiX = limits(2,1):limits(2,2);
mask = trimmedMasks{channelIdx}(roiY,roiX);

image = double(rawFrame)-background;
imageCut = image(roiY,roiX);
localVariance = stdfilt(imageCut,true(windowSize)).^2;
meanIntensity = mean(imageCut(mask));
fitA = calibration.fitI_A_byCh{channelIdx}(roiY,roiX);
fitB = calibration.fitI_B_byCh{channelIdx}(roiY,roiX);
fittedIntensity = fitA.*meanIntensity+fitB;
denominator = fittedIntensity.^2;
correctedNumerator = localVariance-actualGain.*fittedIntensity- ...
    calibration.spVar(roiY,roiX)-darkVariancePerWindow(roiY,roiX);
withoutQuantization = mean(correctedNumerator(mask)./denominator(mask));
withQuantization = mean((correctedNumerator(mask)-1/12)./denominator(mask));
end


function localCreateFixture(recordingDirectory,darkDirectory,isMultipleExposure)
if isMultipleExposure
    exposureSequenceUs = [1000 10000];
    mainExposureUs = repmat(exposureSequenceUs,1,4);
    mainSetIds = repmat([0 1],1,4);
    darkExposureUs = repmat(exposureSequenceUs,1,400);
    darkSetIds = repmat([0 1],1,400);
    exposureMode = 'sequencer';
else
    exposureSequenceUs = 1000;
    mainExposureUs = 1000*ones(1,8);
    mainSetIds = zeros(1,8);
    darkExposureUs = 1000*ones(1,400);
    darkSetIds = zeros(1,400);
    exposureMode = 'fixed';
end

localWriteSyntheticFrames(fullfile(recordingDirectory,'frames.npy'), ...
    numel(mainExposureUs),false,isMultipleExposure);
localWriteSyntheticFrames(fullfile(darkDirectory,'frames.npy'), ...
    numel(darkExposureUs),true,isMultipleExposure);
localWriteVector(fullfile(recordingDirectory,'timestamps_camera_us.npy'), ...
    (0:numel(mainExposureUs)-1)*10000,'float64');
localWriteVector(fullfile(recordingDirectory,'exposure_times_us.npy'), ...
    mainExposureUs,'float64');
localWriteVector(fullfile(recordingDirectory,'sequencer_set_ids.npy'), ...
    mainSetIds,'int64');
localWriteVector(fullfile(darkDirectory,'timestamps_camera_us.npy'), ...
    (0:numel(darkExposureUs)-1)*10000,'float64');
localWriteVector(fullfile(darkDirectory,'exposure_times_us.npy'), ...
    darkExposureUs,'float64');
localWriteVector(fullfile(darkDirectory,'sequencer_set_ids.npy'), ...
    darkSetIds,'int64');
localWriteMetadata(recordingDirectory,exposureMode,exposureSequenceUs);
localWriteMetadata(darkDirectory,exposureMode,exposureSequenceUs);
end


function masks = localMasks(imageSize)
masks = {false(imageSize),false(imageSize)};
masks{1}(3:7,3:5) = true;
masks{2}(5:9,8:10) = true;
end


function localWriteSyntheticFrames(path,frameCount,isDark,isMultipleExposure)
np = py.importlib.import_module('numpy');
shape = py.tuple({int64(frameCount),int64(12),int64(12)});
frameShape = py.tuple({int64(frameCount),int64(1),int64(1)});
xShape = py.tuple({int64(1),int64(1),int64(12)});
yShape = py.tuple({int64(1),int64(12),int64(1)});
frameIndex = np.arange(int64(frameCount),pyargs('dtype','float64')).reshape(frameShape);
xGrid = np.arange(int64(12),pyargs('dtype','float64')).reshape(xShape);
yGrid = np.arange(int64(12),pyargs('dtype','float64')).reshape(yShape);
if isDark
    array = np.full(shape,100,pyargs('dtype','float64'));
    array = np.add(array,np.mod(frameIndex,3));
    array = np.add(array,np.mod(np.add(xGrid,yGrid),2));
    if isMultipleExposure
        array = np.add(array,np.multiply(np.mod(frameIndex,2),2));
    end
else
    array = np.full(shape,1200,pyargs('dtype','float64'));
    array = np.add(array,np.multiply(frameIndex,12));
    leftRegion = np.less(xGrid,6);
    array = np.add(array,np.multiply(leftRegion,np.multiply(frameIndex,35)));
    array = np.add(array,np.multiply(np.mod(np.add(xGrid,np.multiply(yGrid,2)),7),3));
    if isMultipleExposure
        array = np.add(array,np.multiply(np.mod(frameIndex,2),250));
    end
end
array = array.astype('uint16');
np.save(path,array,pyargs('allow_pickle',false));
end


function localWriteVector(path,values,dtypeName)
np = py.importlib.import_module('numpy');
pythonValues = py.list(num2cell(values(:)'));
array = np.array(pythonValues,pyargs('dtype',dtypeName));
np.save(path,array,pyargs('allow_pickle',false));
end


function localWriteMetadata(folder,exposureMode,exposureSequenceUs)
config = struct('acquisition_frame_rate',100,'black_level',0,'gain',8);
if strcmp(exposureMode,'sequencer')
    config.exposure_times_us = exposureSequenceUs;
else
    config.exposure_time = exposureSequenceUs;
end
metadata = struct( ...
    'exposure_mode',exposureMode, ...
    'exposure_sequence_us',exposureSequenceUs, ...
    'camera_serial_number','25268932', ...
    'camera_model','acA1440-220um', ...
    'config',config);
fileId = fopen(fullfile(folder,'metadata.json'),'w');
if fileId < 0
    error('testScosRoiNoiseCorrection:Fixture','Could not write metadata.json.');
end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId,jsonencode(metadata),'char');
end
