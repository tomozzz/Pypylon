function [timeVec,rawSpeckleContrast,corrSpeckleContrast,meanVec,info,results,nirs] = ...
    SCOSNIRSvsTime_WithNoiseSubtraction_Ver2( ...
        recName,backgroundName,windowSize,plotFlag,maskInput,nirsOptions)
%SCOSNIRSVSTIME_WITHNOISESUBTRACTION_VER2 Run SCOS and two-wavelength NIRS.
%   This function reuses SCOSvsTime_WithNoiseSubtraction_Ver2 for NPY
%   loading, exposure-aware noise correction, contrast, BFI, and rBFI. It
%   then uses the saved Sequencer Set ID and camera timestamps to pair two
%   wavelength states and calculate HbO, HbR, StO2, rOEF, and rMRO2.
%
%   Example:
%     options = struct( ...
%         'wavelengthsNm',[785 830], ...
%         'wavelengthSetIds',[0 1], ...
%         'sourceDetectorChannels',[1 2], ...
%         'sourceDetectorDistancesCm',[2 3], ...
%         'baselineDurationS',60);
%     [~,~,~,~,~,results,nirs] = ...
%       SCOSNIRSvsTime_WithNoiseSubtraction_Ver2( ...
%         recName,darkName,7,false,masks,options);
%
%   ROI channel 1 is assumed to be the short-distance detector and channel
%   2 the long-distance detector unless overridden. Set 0/1 to 785/830 nm
%   is an explicit acquisition-system assumption, not information contained
%   in GenICam metadata. Physical LED/laser switching must be synchronized
%   with the camera Sequencer.

if nargin < 6 || isempty(nirsOptions)
    nirsOptions = struct();
end
if ~isstruct(nirsOptions) || ~isscalar(nirsOptions)
    error('SCOSNIRSvsTime:Options','nirsOptions must be a scalar structure.');
end
usePrecomputedResults = isfield(nirsOptions,'precomputedResults') && ...
    ~isempty(nirsOptions.precomputedResults);
if (nargin < 1 || isempty(recName)) && ~usePrecomputedResults
    error('SCOSNIRSvsTime:RecordingRequired', ...
        'recName is required for reproducible NPY SCOS-NIRS analysis.');
end
if nargin < 1 || isempty(recName)
    recName = 'precomputed-results';
end
if nargin < 2
    backgroundName = [];
end
if nargin < 3 || isempty(windowSize)
    windowSize = 7;
end
if nargin < 4 || isempty(plotFlag)
    plotFlag = true;
end

scriptDirectory = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDirectory,'baseFunc'));

if usePrecomputedResults
    results = nirsOptions.precomputedResults;
    calculationOptions = rmfield(nirsOptions,'precomputedResults');
    timeVec = [];
    rawSpeckleContrast = {};
    corrSpeckleContrast = {};
    meanVec = {};
    info = struct('analysisMode','precomputedResults');
else
    calculationOptions = nirsOptions;
    if nargin >= 5 && ~isempty(maskInput)
        [timeVec,rawSpeckleContrast,corrSpeckleContrast,meanVec,info,results] = ...
            SCOSvsTime_WithNoiseSubtraction_Ver2( ...
                recName,backgroundName,windowSize,plotFlag,maskInput);
    else
        [timeVec,rawSpeckleContrast,corrSpeckleContrast,meanVec,info,results] = ...
            SCOSvsTime_WithNoiseSubtraction_Ver2( ...
                recName,backgroundName,windowSize,plotFlag);
    end
end

nirs = localCalculateNirsFromScosResults(results,calculationOptions);
results.nirs = nirs;

if exist(recName,'dir') == 7
    outputDirectory = recName;
else
    outputDirectory = fileparts(recName);
end
if isempty(outputDirectory)
    outputDirectory = pwd;
end

saveOutput = localLogicalOption(nirsOptions,'saveOutput',true);
plotNirs = localLogicalOption(nirsOptions,'plotNirs',logical(plotFlag));
if saveOutput
    outputFile = fullfile(outputDirectory,'SCOSNIRS_output.mat');
    nirsOptionsForSave = calculationOptions;
    save(outputFile,'nirs','results','info','recName','backgroundName', ...
        'windowSize','nirsOptionsForSave','-v7.3');
    fprintf('[SCOS-NIRS] Saved %s\n',outputFile);
end
if plotNirs
    localPlotNirs(nirs,recName,outputDirectory);
end
end


function value = localLogicalOption(options,name,defaultValue)
if isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
    if ~(islogical(value) && isscalar(value)) && ...
            ~(isnumeric(value) && isscalar(value) && isfinite(value) && ismember(value,[0 1]))
        error('SCOSNIRSvsTime:Option', ...
            'options.%s must be a scalar logical value.',name);
    end
    value = logical(value);
else
    value = logical(defaultValue);
end
end


function localPlotNirs(nirs,recName,outputDirectory)
if isempty(nirs.timeVec)
    return
end
timeToPlot = nirs.timeVec;
timeLabel = 'Time [s]';
if timeToPlot(end) - timeToPlot(1) > 120
    timeToPlot = timeToPlot ./ 60;
    timeLabel = 'Time [min]';
end

figureHandle = figure('Name',['SCOS-NIRS: ' char(recName)], ...
    'Units','normalized','Position',[0.1 0.08 0.65 0.78]);
subplot(4,1,1);
plot(timeToPlot,nirs.HbO,'DisplayName','HbO'); hold on;
plot(timeToPlot,nirs.HbR,'DisplayName','HbR');
ylabel('Hb [model units]'); legend('Location','best'); grid on;
title(char(recName),'Interpreter','none');

subplot(4,1,2);
plot(timeToPlot,nirs.StO2);
ylabel('StO2 [%]'); grid on;

subplot(4,1,3);
plot(timeToPlot,nirs.rOEF,'DisplayName','rOEF'); hold on;
plot(timeToPlot,nirs.rBFI,'DisplayName','rBFI');
ylabel('Relative'); legend('Location','best'); grid on;

subplot(4,1,4);
plot(timeToPlot,nirs.rMRO2);
ylabel('rMRO2'); xlabel(timeLabel); grid on;

figurePath = fullfile(outputDirectory,'SCOSNIRS_Hb_StO2_rOEF_rMRO2.fig');
savefig(figureHandle,figurePath);
try
    exportgraphics(figureHandle, ...
        fullfile(outputDirectory,'SCOSNIRS_Hb_StO2_rOEF_rMRO2.png'));
catch exportError
    warning('SCOSNIRSvsTime:PlotExport','PNG export failed: %s',exportError.message);
end
end

function nirs = localCalculateNirsFromScosResults(results,options)
%LOCALCALCULATENIRS Calculate two-wavelength NIRS and CMRO2 surrogates.
%   NIRS = CALCULATENIRSFROMSCOSRESULTS(RESULTS,OPTIONS) consumes the
%   exposure-separated RESULTS returned by SCOSvsTime_WithNoiseSubtraction_Ver2.
%   Wavelength frames are selected with saved Sequencer Set IDs, never frame
%   parity. Two source-detector ROI channels provide the spatial attenuation
%   slope for each wavelength.
%
%   Important OPTIONS fields (defaults shown):
%     wavelengthsNm             [785 830]
%     wavelengthSetIds          [0 1] when available
%     sourceDetectorChannels    [1 2]   % short, long ROI columns
%     sourceDetectorDistancesCm [2 3]
%     extinctionMatrix          [0.08 0.10; 0.11 0.08]
%     baselineDurationS         60
%     pairingToleranceS         []      % inferred from timestamps
%
%   HbO/HbR units follow the supplied extinction matrix. The defaults mirror
%   the legacy SCOS-NIRS calculation and must be replaced by calibrated
%   coefficients before interpreting concentrations quantitatively.

if nargin < 2 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('CalculateNirsFromScosResults:Options', ...
        'options must be a scalar structure.');
end

options = localApplyDefaults(options);
localValidateOptions(options);
frames = localFlattenResults(results);

observedSetIds = unique(frames.sequencerSetId( ...
    isfinite(frames.sequencerSetId) & frames.sequencerSetId >= 0));
if isempty(options.wavelengthSetIds)
    if all(ismember([0;1],observedSetIds))
        wavelengthSetIds = [0 1];
        mappingMessage = ['wavelengthSetIds was not specified; assuming Set 0 = ' ...
            'first wavelength and Set 1 = second wavelength.'];
    elseif numel(observedSetIds) == 2
        wavelengthSetIds = reshape(sort(observedSetIds),1,2);
        mappingMessage = sprintf( ...
            'wavelengthSetIds was inferred as [%g %g] from the two observed Set IDs.', ...
            wavelengthSetIds(1),wavelengthSetIds(2));
    else
        error('CalculateNirsFromScosResults:WavelengthMapping', ...
            ['Unable to infer two wavelength states from Sequencer Set IDs. ' ...
             'Specify options.wavelengthSetIds = [setForLambda1 setForLambda2].']);
    end
    warning('CalculateNirsFromScosResults:AssumedWavelengthMapping','%s',mappingMessage);
else
    wavelengthSetIds = reshape(double(options.wavelengthSetIds),1,2);
    mappingMessage = sprintf('Explicit mapping: Set %g = %g nm, Set %g = %g nm.', ...
        wavelengthSetIds(1),options.wavelengthsNm(1), ...
        wavelengthSetIds(2),options.wavelengthsNm(2));
end

stateRows = cell(1,2);
for wavelengthIdx = 1:2
    stateRows{wavelengthIdx} = find(frames.sequencerSetId == wavelengthSetIds(wavelengthIdx));
    if isempty(stateRows{wavelengthIdx})
        error('CalculateNirsFromScosResults:MissingWavelengthFrames', ...
            'No analyzed frames have Sequencer Set ID %g.',wavelengthSetIds(wavelengthIdx));
    end
end

% Sequencer sets advance in ascending ID order. Pair the lower-ID state with
% the higher-ID state inside the same cycle, then restore wavelength order.
if wavelengthSetIds(1) < wavelengthSetIds(2)
    firstWavelengthIdx = 1;
    secondWavelengthIdx = 2;
else
    firstWavelengthIdx = 2;
    secondWavelengthIdx = 1;
end
firstRows = stateRows{firstWavelengthIdx};
secondRows = stateRows{secondWavelengthIdx};
[firstPairPositions,secondPairPositions,pairingToleranceS] = localPairCycles( ...
    frames.frameIndex(firstRows),frames.timeVec(firstRows), ...
    frames.frameIndex(secondRows),frames.timeVec(secondRows), ...
    options.pairingToleranceS);
if isempty(firstPairPositions)
    error('CalculateNirsFromScosResults:NoPairs', ...
        'No timestamp-consistent wavelength pairs were found.');
end

pairedRows = nan(numel(firstPairPositions),2);
pairedRows(:,firstWavelengthIdx) = firstRows(firstPairPositions);
pairedRows(:,secondWavelengthIdx) = secondRows(secondPairPositions);
pairedRows = round(pairedRows);

shortChannel = options.sourceDetectorChannels(1);
longChannel = options.sourceDetectorChannels(2);
if size(frames.meanIntensity,2) < max(options.sourceDetectorChannels)
    error('CalculateNirsFromScosResults:ChannelCount', ...
        ['SCOS results contain %d ROI channel(s), but sourceDetectorChannels ' ...
         'requests channel %d.'],size(frames.meanIntensity,2),max(options.sourceDetectorChannels));
end

nPairs = size(pairedRows,1);
intensityShort = nan(nPairs,2);
intensityLong = nan(nPairs,2);
bfiByWavelength = nan(nPairs,2);
actualExposureTimesUs = nan(nPairs,2);
frameIndices = nan(nPairs,2);
frameTimes = nan(nPairs,2);
for wavelengthIdx = 1:2
    rows = pairedRows(:,wavelengthIdx);
    intensityShort(:,wavelengthIdx) = frames.meanIntensity(rows,shortChannel);
    intensityLong(:,wavelengthIdx) = frames.meanIntensity(rows,longChannel);
    bfiByWavelength(:,wavelengthIdx) = frames.BFI(rows,longChannel);
    actualExposureTimesUs(:,wavelengthIdx) = frames.exposureTimeUs(rows);
    frameIndices(:,wavelengthIdx) = frames.frameIndex(rows);
    frameTimes(:,wavelengthIdx) = frames.timeVec(rows);
end
timeVec = mean(frameTimes,2);

validIntensityMask = all(isfinite(intensityShort) & intensityShort > 0 & ...
    isfinite(intensityLong) & intensityLong > 0,2);
if ~all(validIntensityMask)
    warning('CalculateNirsFromScosResults:InvalidIntensity', ...
        '%d wavelength pair(s) contain nonpositive or nonfinite intensity and return NaN.', ...
        nnz(~validIntensityMask));
end
if ~any(validIntensityMask)
    error('CalculateNirsFromScosResults:NoValidIntensity', ...
        'No wavelength pair has finite positive short- and long-distance intensity.');
end

distanceDifferenceMm = diff(options.sourceDetectorDistancesCm) * 10;
attenuationSlopePerMm = nan(nPairs,2);
attenuationSlopePerMm(validIntensityMask,:) = ...
    (log10(intensityShort(validIntensityMask,:)) - ...
     log10(intensityLong(validIntensityMask,:))) ./ distanceDifferenceMm;

reducedScatteringPerMm = options.reducedScatteringIntercept - ...
    options.reducedScatteringSlopePerNm .* options.wavelengthsNm;
muAperMm = nan(nPairs,2);
shortDistanceMm = options.sourceDetectorDistancesCm(1) * 10;
for wavelengthIdx = 1:2
    term = log(10) .* attenuationSlopePerMm(:,wavelengthIdx) - 2 / shortDistanceMm;
    muAperMm(:,wavelengthIdx) = term.^2 ./ (3 * reducedScatteringPerMm(wavelengthIdx));
end

hemoglobin = nan(nPairs,2);
hemoglobin(validIntensityMask,:) = ...
    (options.extinctionMatrix \ muAperMm(validIntensityMask,:).').';
HbO = hemoglobin(:,1);
HbR = hemoglobin(:,2);
denominator = HbO + HbR;
StO2 = 100 .* HbO ./ denominator;
StO2(~isfinite(StO2) | abs(denominator) <= eps) = NaN;
OEF = 1 - StO2 ./ 100;

baselineMask = timeVec <= timeVec(1) + options.baselineDurationS;
baselineOEF = localFiniteMean(OEF(baselineMask));
if ~isfinite(baselineOEF) || abs(baselineOEF) <= eps
    warning('CalculateNirsFromScosResults:InvalidOefBaseline', ...
        'The baseline OEF is invalid; rOEF and rMRO2 return NaN.');
    rOEF = nan(size(OEF));
else
    rOEF = OEF ./ baselineOEF;
end

bfiByWavelength(~isfinite(bfiByWavelength) | bfiByWavelength <= 0) = NaN;
combinedBFI = mean(bfiByWavelength,2,'omitnan');
combinedBFI(all(isnan(bfiByWavelength),2)) = NaN;
baselineBFI = localFiniteMean(combinedBFI(baselineMask));
if ~isfinite(baselineBFI) || baselineBFI <= 0
    warning('CalculateNirsFromScosResults:InvalidBfiBaseline', ...
        'The baseline BFI is invalid; rBFI and rMRO2 return NaN.');
    rBFI = nan(size(combinedBFI));
else
    rBFI = combinedBFI ./ baselineBFI;
end
rMRO2 = rOEF .* rBFI;

nirs = struct();
nirs.timeVec = timeVec;
nirs.frameTimes = frameTimes;
nirs.frameIndices = frameIndices;
nirs.pairTimeDifferenceS = abs(diff(frameTimes,1,2));
nirs.pairingToleranceS = pairingToleranceS;
nirs.wavelengthsNm = reshape(options.wavelengthsNm,1,2);
nirs.wavelengthSetIds = wavelengthSetIds;
nirs.wavelengthMapping = mappingMessage;
nirs.sourceDetectorChannels = reshape(options.sourceDetectorChannels,1,2);
nirs.sourceDetectorDistancesCm = reshape(options.sourceDetectorDistancesCm,1,2);
nirs.intensityShort = intensityShort;
nirs.intensityLong = intensityLong;
nirs.actualExposureTimesUs = actualExposureTimesUs;
nirs.attenuationSlopePerMm = attenuationSlopePerMm;
nirs.reducedScatteringPerMm = reducedScatteringPerMm;
nirs.muAperMm = muAperMm;
nirs.extinctionMatrix = options.extinctionMatrix;
nirs.HbO = HbO;
nirs.HbR = HbR;
nirs.StO2 = StO2;
nirs.OEF = OEF;
nirs.rOEF = rOEF;
nirs.BFIByWavelength = bfiByWavelength;
nirs.BFI = combinedBFI;
nirs.rBFI = rBFI;
nirs.rMRO2 = rMRO2;
nirs.baselineMask = baselineMask;
nirs.baselineDurationS = options.baselineDurationS;
nirs.baselineOEF = baselineOEF;
nirs.baselineBFI = baselineBFI;
nirs.validPairMask = validIntensityMask;
nirs.options = options;
nirs.modelNote = ['Spatially resolved two-distance model. HbO/HbR units depend on ' ...
    'the supplied extinction matrix; rOEF and rMRO2 are baseline-relative surrogates.'];
end


function options = localApplyDefaults(options)
defaults = struct( ...
    'wavelengthsNm',[785 830], ...
    'wavelengthSetIds',[], ...
    'sourceDetectorChannels',[1 2], ...
    'sourceDetectorDistancesCm',[2 3], ...
    'extinctionMatrix',[0.08 0.10; 0.11 0.08], ...
    'baselineDurationS',60, ...
    'pairingToleranceS',[], ...
    'reducedScatteringIntercept',1, ...
    'reducedScatteringSlopePerNm',5.9e-4);
names = fieldnames(defaults);
for idx = 1:numel(names)
    if ~isfield(options,names{idx}) || isempty(options.(names{idx}))
        options.(names{idx}) = defaults.(names{idx});
    end
end
end


function localValidateOptions(options)
validateattributes(options.wavelengthsNm,{'numeric'},{'real','finite','positive','numel',2});
if ~isempty(options.wavelengthSetIds)
    validateattributes(options.wavelengthSetIds,{'numeric'}, ...
        {'real','finite','integer','nonnegative','numel',2});
    if options.wavelengthSetIds(1) == options.wavelengthSetIds(2)
        error('CalculateNirsFromScosResults:WavelengthSetIds', ...
            'wavelengthSetIds must contain two different Set IDs.');
    end
end
validateattributes(options.sourceDetectorChannels,{'numeric'}, ...
    {'real','finite','integer','positive','numel',2});
if options.sourceDetectorChannels(1) == options.sourceDetectorChannels(2)
    error('CalculateNirsFromScosResults:Channels', ...
        'sourceDetectorChannels must contain different short and long ROI channels.');
end
validateattributes(options.sourceDetectorDistancesCm,{'numeric'}, ...
    {'real','finite','positive','numel',2});
if options.sourceDetectorDistancesCm(2) <= options.sourceDetectorDistancesCm(1)
    error('CalculateNirsFromScosResults:Distances', ...
        'sourceDetectorDistancesCm must be [short long] with long > short.');
end
validateattributes(options.extinctionMatrix,{'numeric'},{'real','finite','size',[2 2]});
if rcond(double(options.extinctionMatrix)) <= eps
    error('CalculateNirsFromScosResults:ExtinctionMatrix', ...
        'extinctionMatrix must be nonsingular.');
end
validateattributes(options.baselineDurationS,{'numeric'}, ...
    {'real','finite','positive','scalar'});
if ~isempty(options.pairingToleranceS)
    validateattributes(options.pairingToleranceS,{'numeric'}, ...
        {'real','finite','positive','scalar'});
end
validateattributes(options.reducedScatteringIntercept,{'numeric'}, ...
    {'real','finite','scalar'});
validateattributes(options.reducedScatteringSlopePerNm,{'numeric'}, ...
    {'real','finite','nonnegative','scalar'});
reducedScattering = options.reducedScatteringIntercept - ...
    options.reducedScatteringSlopePerNm .* options.wavelengthsNm;
if any(reducedScattering <= 0)
    error('CalculateNirsFromScosResults:ReducedScattering', ...
        'The reduced-scattering model must stay positive at both wavelengths.');
end
end


function frames = localFlattenResults(results)
if ~isstruct(results) || ~isfield(results,'byExposure') || isempty(results.byExposure)
    error('CalculateNirsFromScosResults:Results', ...
        'results.byExposure from SCOS analysis is required.');
end

frameIndex = [];
timeVec = [];
sequencerSetId = [];
exposureTimeUs = [];
meanIntensity = [];
BFI = [];
nChannels = [];
for exposureIdx = 1:numel(results.byExposure)
    series = results.byExposure(exposureIdx);
    required = {'frameIndices','timeVec','meanIntensity','BFI'};
    for fieldIdx = 1:numel(required)
        if ~isfield(series,required{fieldIdx})
            error('CalculateNirsFromScosResults:ResultsField', ...
                'results.byExposure(%d).%s is required.',exposureIdx,required{fieldIdx});
        end
    end
    count = numel(series.frameIndices);
    if size(series.meanIntensity,1) ~= count || size(series.BFI,1) ~= count || ...
            numel(series.timeVec) ~= count
        error('CalculateNirsFromScosResults:ResultsLength', ...
            'SCOS result arrays have inconsistent lengths in exposure group %d.',exposureIdx);
    end
    if isempty(nChannels)
        nChannels = size(series.meanIntensity,2);
    elseif size(series.meanIntensity,2) ~= nChannels || size(series.BFI,2) ~= nChannels
        error('CalculateNirsFromScosResults:ResultsChannels', ...
            'SCOS exposure groups have inconsistent ROI channel counts.');
    end

    if isfield(series,'sequencerSetIds') && ~isempty(series.sequencerSetIds)
        setIds = double(series.sequencerSetIds(:));
        if numel(setIds) ~= count
            error('CalculateNirsFromScosResults:SetIdLength', ...
                'sequencerSetIds length differs from frame count in exposure group %d.',exposureIdx);
        end
    else
        setIds = nan(count,1);
    end
    if isfield(series,'actualExposureTimesUs') && ~isempty(series.actualExposureTimesUs)
        exposure = double(series.actualExposureTimesUs(:));
        if numel(exposure) ~= count
            error('CalculateNirsFromScosResults:ExposureLength', ...
                'actualExposureTimesUs length differs from frame count in exposure group %d.',exposureIdx);
        end
    elseif isfield(series,'exposureTimeUs') && isscalar(series.exposureTimeUs)
        exposure = repmat(double(series.exposureTimeUs),count,1);
    else
        exposure = nan(count,1);
    end

    frameIndex = [frameIndex; double(series.frameIndices(:))]; %#ok<AGROW>
    timeVec = [timeVec; double(series.timeVec(:))]; %#ok<AGROW>
    sequencerSetId = [sequencerSetId; setIds]; %#ok<AGROW>
    exposureTimeUs = [exposureTimeUs; exposure]; %#ok<AGROW>
    meanIntensity = [meanIntensity; double(series.meanIntensity)]; %#ok<AGROW>
    BFI = [BFI; double(series.BFI)]; %#ok<AGROW>
end

if any(~isfinite(frameIndex)) || any(frameIndex < 1) || any(frameIndex ~= round(frameIndex)) || ...
        numel(unique(frameIndex)) ~= numel(frameIndex)
    error('CalculateNirsFromScosResults:FrameIndices', ...
        'frameIndices must be unique positive 1-based integers.');
end
if any(~isfinite(timeVec))
    error('CalculateNirsFromScosResults:Timestamps', ...
        'Finite camera-derived or fallback timestamps are required for wavelength pairing.');
end
[frameIndex,order] = sort(frameIndex);
timeVec = timeVec(order);
if any(diff(timeVec) <= 0)
    error('CalculateNirsFromScosResults:Timestamps', ...
        'SCOS frame timestamps must be strictly increasing in frame order.');
end
frames = struct( ...
    'frameIndex',frameIndex, ...
    'timeVec',timeVec, ...
    'sequencerSetId',sequencerSetId(order), ...
    'exposureTimeUs',exposureTimeUs(order), ...
    'meanIntensity',meanIntensity(order,:), ...
    'BFI',BFI(order,:));
end


function [firstPositions,secondPositions,toleranceS] = localPairCycles( ...
        firstFrameIndices,firstTimes,secondFrameIndices,secondTimes,requestedToleranceS)
if isempty(requestedToleranceS)
    periods = [];
    if numel(firstTimes) > 1
        periods(end+1) = median(diff(firstTimes));
    end
    if numel(secondTimes) > 1
        periods(end+1) = median(diff(secondTimes));
    end
    periods = periods(isfinite(periods) & periods > 0);
    if isempty(periods)
        toleranceS = inf;
    else
        toleranceS = 1.05 * min(periods);
    end
else
    toleranceS = double(requestedToleranceS);
end

firstPositions = zeros(0,1);
secondPositions = zeros(0,1);
secondIdx = 1;
for firstIdx = 1:numel(firstFrameIndices)
    while secondIdx <= numel(secondFrameIndices) && ...
            secondFrameIndices(secondIdx) < firstFrameIndices(firstIdx)
        secondIdx = secondIdx + 1;
    end
    if secondIdx > numel(secondFrameIndices)
        break
    end
    if firstIdx < numel(firstFrameIndices)
        nextFirstFrame = firstFrameIndices(firstIdx+1);
    else
        nextFirstFrame = inf;
    end
    if secondFrameIndices(secondIdx) >= nextFirstFrame
        continue
    end
    timeDifference = secondTimes(secondIdx) - firstTimes(firstIdx);
    if timeDifference >= 0 && timeDifference <= toleranceS + eps(max(abs(secondTimes(secondIdx)),1))
        firstPositions(end+1,1) = firstIdx; %#ok<AGROW>
        secondPositions(end+1,1) = secondIdx; %#ok<AGROW>
    end
    secondIdx = secondIdx + 1;
end
end


function value = localFiniteMean(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end
