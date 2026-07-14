function tests = testNirsFromScosResults
tests = functiontests(localfunctions);
end


function setupOnce(~)
analysisDirectory = fileparts(fileparts(mfilename('fullpath')));
addpath(analysisDirectory,fullfile(analysisDirectory,'baseFunc'));
end


function testTwoWavelengthCalculationMatchesReferenceFormula(testCase)
results = localSyntheticResults(false);
options = localOptions();

nirs = localRunPrecomputed(results,options);

verifyEqual(testCase,nirs.frameIndices,[1 2;3 4;5 6]);
verifyEqual(testCase,nirs.timeVec,[0.025;0.225;0.425],'AbsTol',1e-12);
verifyEqual(testCase,nirs.wavelengthSetIds,[0 1]);
verifyEqual(testCase,nirs.intensityShort(1,:),[1000 1100]);
verifyEqual(testCase,nirs.intensityLong(1,:),[400 450]);

slope = [(log10(1000)-log10(400))/10, ...
         (log10(1100)-log10(450))/10];
muSp = 1 - 5.9e-4 .* [785 830];
muA = (log(10).*slope - 2/20).^2 ./ (3.*muSp);
expectedHb = (options.extinctionMatrix \ muA.').';
expectedStO2 = 100 * expectedHb(1) / sum(expectedHb);
verifyEqual(testCase,nirs.muAperMm(1,:),muA,'RelTol',1e-12);
verifyEqual(testCase,[nirs.HbO(1) nirs.HbR(1)],expectedHb,'RelTol',1e-12);
verifyEqual(testCase,nirs.StO2(1),expectedStO2,'RelTol',1e-12);
verifyEqual(testCase,nirs.rOEF(1),1,'AbsTol',1e-12);
verifyEqual(testCase,nirs.rBFI(1),1,'AbsTol',1e-12);
verifyEqual(testCase,nirs.rMRO2(1),1,'AbsTol',1e-12);
end


function testDroppedWavelengthFrameDoesNotShiftFollowingPairs(testCase)
results = localSyntheticResults(true);
options = localOptions();

nirs = localRunPrecomputed(results,options);

verifyEqual(testCase,nirs.frameIndices,[1 2;5 6]);
verifyEqual(testCase,size(nirs.frameIndices),[2 2]);
end


function testSetIdsSplitWavelengthsInsideOneExposureGroup(testCase)
splitResults = localSyntheticResults(false);
first = splitResults.byExposure(1);
second = splitResults.byExposure(2);
combined = struct();
combined.frameIndices = (1:6)';
combined.timeVec = reshape([first.timeVec.'; second.timeVec.'],[],1);
combined.meanIntensity = reshape(permute(cat(3,first.meanIntensity,second.meanIntensity), ...
    [3 1 2]),6,2);
combined.BFI = reshape(permute(cat(3,first.BFI,second.BFI),[3 1 2]),6,2);
combined.sequencerSetIds = repmat([0;1],3,1);
combined.actualExposureTimesUs = 1000*ones(6,1);
combined.exposureTimeUs = 1000;
results = struct('byExposure',combined);

nirs = localRunPrecomputed(results,localOptions());

verifyEqual(testCase,nirs.frameIndices,[1 2;3 4;5 6]);
verifyEqual(testCase,nirs.wavelengthSetIds,[0 1]);
verifyEqual(testCase,nirs.intensityShort(1,:),[1000 1100]);
end


function testReversedWavelengthMappingPreservesSequencePairing(testCase)
results = localSyntheticResults(false);
options = localOptions();
options.wavelengthSetIds = [1 0];

nirs = localRunPrecomputed(results,options);

verifyEqual(testCase,nirs.frameIndices,[2 1;4 3;6 5]);
verifyEqual(testCase,nirs.intensityShort(1,:),[1100 1000]);
end


function testNonpositiveIntensityBecomesInvalidPair(testCase)
results = localSyntheticResults(false);
results.byExposure(1).meanIntensity(2,1) = 0;
options = localOptions();

warningState = warning('off','CalculateNirsFromScosResults:InvalidIntensity');
cleanup = onCleanup(@() warning(warningState));
nirs = localRunPrecomputed(results,options);

verifyEqual(testCase,nirs.validPairMask,[true;false;true]);
verifyTrue(testCase,isnan(nirs.StO2(2)));
end


function testMissingSetIdsAreRejected(testCase)
results = localSyntheticResults(false);
results.byExposure(1).sequencerSetIds = [];
results.byExposure(2).sequencerSetIds = [];

verifyError(testCase,@() localRunPrecomputed(results,localOptions()), ...
    'CalculateNirsFromScosResults:MissingWavelengthFrames');
end


function testRequestedRoiChannelsAreValidated(testCase)
results = localSyntheticResults(false);
options = localOptions();
options.sourceDetectorChannels = [1 3];

verifyError(testCase,@() localRunPrecomputed(results,options), ...
    'CalculateNirsFromScosResults:ChannelCount');
end


function testPublicWrapperSignature(testCase)
verifyEqual(testCase,nargin('SCOSNIRSvsTime_WithNoiseSubtraction_Ver2'),6);
verifyEqual(testCase,nargout('SCOSNIRSvsTime_WithNoiseSubtraction_Ver2'),7);
end


function options = localOptions()
options = struct( ...
    'wavelengthsNm',[785 830], ...
    'wavelengthSetIds',[0 1], ...
    'sourceDetectorChannels',[1 2], ...
    'sourceDetectorDistancesCm',[2 3], ...
    'extinctionMatrix',[0.08 0.10; 0.11 0.08], ...
    'baselineDurationS',0.1);
end


function nirs = localRunPrecomputed(results,options)
options.precomputedResults = results;
options.saveOutput = false;
options.plotNirs = false;
[~,~,~,~,~,~,nirs] = SCOSNIRSvsTime_WithNoiseSubtraction_Ver2( ...
    'synthetic-results',[],7,false,[],options);
end


function results = localSyntheticResults(withDrop)
series785 = struct();
series785.frameIndices = [1;3;5];
series785.timeVec = [0;0.2;0.4];
series785.meanIntensity = [1000 400; 950 390; 900 380];
series785.BFI = [3 4; 3.3 4.4; 3.6 4.8];
series785.sequencerSetIds = zeros(3,1);
series785.actualExposureTimesUs = 1000*ones(3,1);
series785.exposureTimeUs = 1000;

series830 = struct();
if withDrop
    series830.frameIndices = [2;6];
    series830.timeVec = [0.05;0.45];
    series830.meanIntensity = [1100 450; 1000 430];
    series830.BFI = [4 5; 4.8 6];
    series830.sequencerSetIds = ones(2,1);
    series830.actualExposureTimesUs = 10000*ones(2,1);
else
    series830.frameIndices = [2;4;6];
    series830.timeVec = [0.05;0.25;0.45];
    series830.meanIntensity = [1100 450; 1050 440; 1000 430];
    series830.BFI = [4 5; 4.4 5.5; 4.8 6];
    series830.sequencerSetIds = ones(3,1);
    series830.actualExposureTimesUs = 10000*ones(3,1);
end
series830.exposureTimeUs = 10000;

results = struct();
results.byExposure = [series785 series830];
end
