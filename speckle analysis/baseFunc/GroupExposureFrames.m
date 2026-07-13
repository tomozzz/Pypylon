function [groupIndex, groupExposureTimesUs, details] = GroupExposureFrames(exposureTimesUs, exposureSequenceUs, nFrames)
% GroupExposureFrames Group frames by applied exposure without parity assumptions.
%
% [groupIndex, groupExposureTimesUs, details] = GroupExposureFrames(...)
% groups per-frame Chunk exposure values using the configured exposure
% sequence as canonical values. Comparisons allow small camera quantization
% differences and never depend on odd/even frame numbers. If old recordings
% have no per-frame exposure array, only an effectively single-exposure
% sequence can be represented safely.

if nargin < 1 || isempty(exposureTimesUs)
    exposureTimesUs = [];
else
    validateattributes(exposureTimesUs, {'numeric'}, {'vector','real'}, mfilename, 'exposureTimesUs');
    exposureTimesUs = double(exposureTimesUs(:));
end

if nargin < 2 || isempty(exposureSequenceUs)
    exposureSequenceUs = [];
else
    validateattributes(exposureSequenceUs, {'numeric'}, {'vector','real','finite','positive'}, mfilename, 'exposureSequenceUs');
    exposureSequenceUs = double(exposureSequenceUs(:)');
end

if nargin < 3 || isempty(nFrames)
    nFrames = numel(exposureTimesUs);
end
validateattributes(nFrames, {'numeric'}, {'scalar','integer','nonnegative','finite'}, mfilename, 'nFrames');
nFrames = double(nFrames);

if ~isempty(exposureTimesUs) && numel(exposureTimesUs) ~= nFrames
    error('GroupExposureFrames:LengthMismatch', ...
        'exposureTimesUs contains %d values, but the recording contains %d frames.', ...
        numel(exposureTimesUs), nFrames);
end

[canonicalSequence, sequenceMap] = localStableUnique(exposureSequenceUs);

details = struct();
details.hasPerFrameExposure = ~isempty(exposureTimesUs);
details.requestedSequenceUs = exposureSequenceUs;
details.canonicalSequenceUs = canonicalSequence;
details.sequenceToGroup = sequenceMap;
details.unusedSequenceUs = [];
details.actualMedianUs = [];
details.toleranceUs = [];

if isempty(exposureTimesUs)
    if numel(canonicalSequence) > 1
        error('GroupExposureFrames:MissingPerFrameExposure', ...
            ['The recording declares %d exposure conditions, but has no per-frame ' ...
             'exposure metadata. Exposure groups cannot be inferred safely.'], ...
            numel(canonicalSequence));
    end
    groupIndex = ones(nFrames,1);
    if isempty(canonicalSequence)
        groupExposureTimesUs = NaN;
    else
        groupExposureTimesUs = canonicalSequence;
    end
    details.actualMedianUs = groupExposureTimesUs;
    details.toleranceUs = localTolerance(groupExposureTimesUs, groupExposureTimesUs);
    details.isMultipleExposure = false;
    return;
end

if any(~isfinite(exposureTimesUs)) || any(exposureTimesUs <= 0)
    error('GroupExposureFrames:InvalidPerFrameExposure', ...
        'Per-frame exposure values must all be finite and greater than zero.');
end

if isempty(canonicalSequence)
    [groupExposureTimesUs, groupIndex] = localStableUnique(exposureTimesUs(:)');
    groupIndex = groupIndex(:);
else
    groupExposureTimesUs = canonicalSequence;
    groupIndex = zeros(nFrames,1);
    groupTolerance = localTolerance(groupExposureTimesUs, groupExposureTimesUs);

    for frameIdx = 1:nFrames
        distances = abs(groupExposureTimesUs - exposureTimesUs(frameIdx));
        [distance, nearest] = min(distances);
        if distance > groupTolerance(nearest)
            error('GroupExposureFrames:UnmatchedExposure', ...
                ['Frame %d has applied exposure %.12g us, which does not match any ' ...
                 'configured exposure within tolerance (nearest %.12g us, tolerance %.6g us).'], ...
                frameIdx, exposureTimesUs(frameIdx), groupExposureTimesUs(nearest), groupTolerance(nearest));
        end
        groupIndex(frameIdx) = nearest;
    end

    % A configured set may have no successful GrabResult (for example a
    % short capture or a dropped frame). Keep only observed conditions and
    % record unused configured values instead of failing the whole analysis.
    observedOldGroups = find(arrayfun(@(idx) any(groupIndex == idx),1:numel(groupExposureTimesUs)));
    unusedOldGroups = setdiff(1:numel(groupExposureTimesUs),observedOldGroups,'stable');
    details.unusedSequenceUs = groupExposureTimesUs(unusedOldGroups);
    oldToNew = zeros(1,numel(groupExposureTimesUs));
    oldToNew(observedOldGroups) = 1:numel(observedOldGroups);
    groupIndex = reshape(oldToNew(groupIndex(:)),[],1);
    groupExposureTimesUs = groupExposureTimesUs(observedOldGroups);
    details.sequenceToGroup = oldToNew(sequenceMap);
end

nGroups = numel(groupExposureTimesUs);
actualMedianUs = nan(1,nGroups);
for groupIdx = 1:nGroups
    values = exposureTimesUs(groupIndex == groupIdx);
    actualMedianUs(groupIdx) = median(values);
end

details.actualMedianUs = actualMedianUs;
details.toleranceUs = localTolerance(groupExposureTimesUs, groupExposureTimesUs);
details.isMultipleExposure = nGroups > 1;
end

function [uniqueValues, valueToGroup] = localStableUnique(values)
uniqueValues = zeros(1,0);
valueToGroup = zeros(size(values));
for valueIdx = 1:numel(values)
    value = values(valueIdx);
    if isempty(uniqueValues)
        uniqueValues = value;
        valueToGroup(valueIdx) = 1;
        continue;
    end

    distances = abs(uniqueValues - value);
    tolerances = localTolerance(uniqueValues, value);
    matching = find(distances <= tolerances, 1, 'first');
    if isempty(matching)
        uniqueValues(end+1) = value; %#ok<AGROW>
        valueToGroup(valueIdx) = numel(uniqueValues);
    else
        valueToGroup(valueIdx) = matching;
    end
end
end

function toleranceUs = localTolerance(referenceUs, comparisonUs)
% Basler may quantize ExposureTime slightly. Keep the tolerance small and,
% where multiple requested values exist, strictly below half their spacing.
absoluteToleranceUs = 0.5;
relativeTolerance = 1e-5;
referenceUs = double(referenceUs(:)');
comparisonScale = max(abs(double(comparisonUs(:)')));
if isempty(comparisonScale) || ~isfinite(comparisonScale)
    comparisonScale = 0;
end
toleranceUs = max(absoluteToleranceUs, relativeTolerance .* max(abs(referenceUs), comparisonScale));

if numel(referenceUs) > 1
    for idx = 1:numel(referenceUs)
        otherDistances = abs(referenceUs(idx) - referenceUs([1:idx-1 idx+1:end]));
        minimumGap = min(otherDistances);
        toleranceUs(idx) = min(toleranceUs(idx), 0.49 * minimumGap);
    end
end
end
