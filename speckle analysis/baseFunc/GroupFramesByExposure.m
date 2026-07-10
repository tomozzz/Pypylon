function groups = GroupFramesByExposure(exposureTimesUs,timeVec)
% GroupFramesByExposure Return timestamp-preserving frame groups by exposure.
% Frame parity is never used; grouping is based only on saved per-frame values.

exposureTimesUs = double(exposureTimesUs(:));
timeVec = timeVec(:);
if numel(exposureTimesUs) ~= numel(timeVec)
    error('GroupFramesByExposure:Length', ...
        'Exposure and time vectors must have identical lengths.');
end
uniqueExposureTimesUs = unique(exposureTimesUs,'stable');
groups = struct([]);
for i = 1:numel(uniqueExposureTimesUs)
    if isnan(uniqueExposureTimesUs(i))
        idx = find(isnan(exposureTimesUs));
    else
        idx = find(exposureTimesUs == uniqueExposureTimesUs(i));
    end
    groups(i).exposureTimeUs = uniqueExposureTimesUs(i); %#ok<AGROW>
    groups(i).frameIndices = idx;
    groups(i).timeVec = timeVec(idx);
end
end
